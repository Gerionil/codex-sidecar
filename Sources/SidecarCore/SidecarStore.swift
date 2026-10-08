import Foundation
import Combine

public protocol SidecarCatalog: Sendable {
    var lastStatus: SessionCatalog.Status { get async }
    func sessions(root: URL) async -> AsyncStream<[SessionDescriptor]>
    func stop() async
}
public protocol SidecarReader: Sendable {
    func snapshots() async -> AsyncStream<DerivedSession>
    func select(_ session: SessionDescriptor) async
    func refresh() async
    func stop() async
}
public protocol SidecarQuotas: Sendable {
    func snapshots() async -> AsyncStream<QuotaState>
    func start() async
    func refresh(now: Date) async
    func setOffline(_ enabled: Bool) async
    func wake() async
    func stop() async
}
extension SessionCatalog: SidecarCatalog {}
extension SessionReader: SidecarReader {}
extension QuotaProvider: SidecarQuotas {}

public enum SidecarAppearance: String, Codable, CaseIterable, Sendable { case system, light, dark }

public struct LocalSettings: Codable, Equatable, Sendable {
    public var rootOverride: String?
    public var executableOverride: String?
    public var selectedID: String?
    public var bucketID: String?
    public var offline: Bool
    public var appearance: SidecarAppearance
    public init(rootOverride: String? = nil, executableOverride: String? = nil, selectedID: String? = nil,
                bucketID: String? = nil, offline: Bool = false, appearance: SidecarAppearance = .system) {
        self.rootOverride = rootOverride; self.executableOverride = executableOverride
        self.selectedID = selectedID; self.bucketID = bucketID; self.offline = offline; self.appearance = appearance
    }
    private enum CodingKeys: String, CodingKey { case rootOverride, executableOverride, selectedID, bucketID, offline, appearance }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rootOverride = try c.decodeIfPresent(String.self, forKey: .rootOverride)
        executableOverride = try c.decodeIfPresent(String.self, forKey: .executableOverride)
        selectedID = try c.decodeIfPresent(String.self, forKey: .selectedID)
        bucketID = try c.decodeIfPresent(String.self, forKey: .bucketID)
        offline = try c.decodeIfPresent(Bool.self, forKey: .offline) ?? false
        appearance = (try? c.decodeIfPresent(SidecarAppearance.self, forKey: .appearance)) ?? .system
    }

}
/// Only local settings and opaque selection are persisted. No metrics or account identity.
@MainActor
public final class SettingsPersistence {
    private let defaults: UserDefaults
    private let key = "sidecar.localSettings"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> LocalSettings {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(LocalSettings.self, from: data) else { return LocalSettings() }
        return value
    }
    public func save(_ settings: LocalSettings) { defaults.set(try? JSONEncoder().encode(settings), forKey: key) }
}
public struct SidecarRuntime: Sendable {
    public let root: URL
    public let catalog: any SidecarCatalog
    public let reader: any SidecarReader
    public let quotas: any SidecarQuotas
    public let compatibility: String
    public init(root: URL, catalog: any SidecarCatalog, reader: any SidecarReader, quotas: any SidecarQuotas, compatibility: String) {
        self.root = root; self.catalog = catalog; self.reader = reader; self.quotas = quotas; self.compatibility = compatibility
    }
    func stop() async {
        async let c: Void = catalog.stop()
        async let r: Void = reader.stop()
        async let q: Void = quotas.stop()
        _ = await (c, r, q)
    }
}

/// Providers and subscriptions belong to the app, never to a visible surface.
@MainActor
public final class SidecarStore: ObservableObject {
    public typealias Factory = @Sendable (LocalSettings) async -> SidecarRuntime
    public private(set) var sessionLabels: [String: String] = [:]
    @Published public private(set) var sessions: [SessionDescriptor] = []
    @Published public private(set) var catalogStatus: SessionCatalog.Status?
    @Published public private(set) var session: DerivedSession?
    @Published public private(set) var quota: QuotaState = .loading
    @Published public private(set) var settings: LocalSettings
    @Published public private(set) var chosenRoot: String = "Resolving…"
    @Published public private(set) var compatibility = "Executable not verified"
    @Published public private(set) var requestPage = 0
    private let factory: Factory
    private let persistence: SettingsPersistence?
    private var runtime: SidecarRuntime?
    private var subscriptions: [Task<Void, Never>] = []
    private var transition: Task<Void, Never>?
    private var providerStart: Task<Void, Never>?
    private var generation = 0
    private var started = false
    private var stopped = false
    public var selectedID: String? { settings.selectedID }
    public var selectedDescriptor: SessionDescriptor? { sessions.first { $0.id == selectedID } }
    public var selectedBucketID: String? {
        guard let snapshot = quota.lastGood else { return nil }
        if let pinned = settings.bucketID { return snapshot.buckets.contains { $0.id == pinned } ? pinned : nil }
        return snapshot.defaultBucketID
    }
    public var bucketSelectionStatus: String {
        if let pinned = settings.bucketID, let snapshot = quota.lastGood, !snapshot.buckets.contains(where: { $0.id == pinned }) {
            return "Unavailable — Previously selected bucket no longer returned; choose a bucket"
        }
        return ""
    }
    public var page: RequestPage { RequestPage(session: session, page: requestPage) }
    public var sessionStatus: String {
        switch catalogStatus {
        case nil: return "Loading local chats"
        case .missingRoot: return "Unavailable — Codex root missing"
        case .unreadableRoot: return "Error — Codex root unreadable"
        default: break
        }
        if selectedID == nil { return sessions.isEmpty ? "Unavailable — No local chats found" : "Select a chat manually" }
        guard let session else {
            return selectedDescriptor == nil ? "Unavailable — Pinned chat sources unavailable" : "Loading selected chat"
        }
        switch session.sourceAvailability {
        case .unavailable: return "Unavailable — Selected chat sources missing or unreadable"
        case .partial: return "Stale / partial — Some selected sources unavailable"
        case .available: return catalogStatus == .partial ? "Available — Discovery partially unavailable" : "Available · Local rollout files"
        }
    }
    public init(settings: LocalSettings, persistence: SettingsPersistence? = nil, factory: @escaping Factory = SidecarRuntime.live) {
        self.settings = settings; self.persistence = persistence; self.factory = factory
    }
    public func start() async {
        guard !started, !stopped else { return }
        started = true
        await replaceRuntime()
    }
    /// Clear obsolete display immediately; serialize teardown before constructing replacements.
    private func replaceRuntime() async {
        generation += 1
        let epoch = generation, previous = transition, old = runtime, starts = providerStart
        previous?.cancel()
        runtime = nil; providerStart = nil
        subscriptions.forEach { $0.cancel() }; subscriptions.removeAll()
        starts?.cancel()
        session = nil; sessionLabels = [:]; sessions = []; catalogStatus = nil; quota = settings.offline ? .unavailable(.offline) : .loading
        requestPage = 0; compatibility = "Executable not verified"
        let captured = settings, factory = factory
        let task = Task { [weak self] in
            await previous?.value
            await old?.stop()
            await starts?.value
            guard let self, self.generation == epoch, !self.stopped else { return }
            let new = await factory(captured)
            guard self.generation == epoch, !self.stopped else { await new.stop(); return }
            self.runtime = new; self.chosenRoot = new.root.path; self.compatibility = new.compatibility
            await new.quotas.setOffline(self.settings.offline)
            guard self.generation == epoch, !self.stopped else { await new.stop(); return }
            let catalogStream = await new.catalog.sessions(root: new.root)
            guard self.generation == epoch, !self.stopped else { await new.stop(); return }
            let readerStream = await new.reader.snapshots()
            guard self.generation == epoch, !self.stopped else { await new.stop(); return }
            let quotaStream = await new.quotas.snapshots()
            guard self.generation == epoch, !self.stopped else { await new.stop(); return }
            self.subscriptions = [
                Task { [weak self] in
                    for await items in catalogStream {
                        let labels = await Task.detached(priority: .utility) { PresentationText.descriptors(items) }.value
                        let status = await new.catalog.lastStatus
                        guard let self, !Task.isCancelled, self.generation == epoch else { break }
                        self.sessionLabels = labels; self.sessions = items; self.catalogStatus = status
                        if self.session == nil, let id = self.selectedID, let descriptor = items.first(where: { $0.id == id }) {
                            await new.reader.select(descriptor)
                        }
                    }
                },
                Task { [weak self] in
                    for await value in readerStream {
                        guard let self, !Task.isCancelled, self.generation == epoch else { break }
                        guard value.owningThreadID == self.selectedID else { continue }
                        self.session = value
                        if self.requestPage * 100 >= value.requests.count { self.requestPage = 0 }
                    }
                },
                Task { [weak self] in
                    for await value in quotaStream {
                        guard let self, !Task.isCancelled, self.generation == epoch else { break }
                        self.quota = value
                    }
                }
            ]
            self.providerStart = Task { await new.quotas.start() }
        }
        transition = task
        await task.value
    }
    public func selectSession(id: String) async {
        guard !stopped, let runtime, let descriptor = sessions.first(where: { $0.id == id }) else { return }
        if settings.selectedID == id { return }
        settings.selectedID = id; persistence?.save(settings)
        session = nil; requestPage = 0
        await runtime.reader.select(descriptor)
    }
    public func setAppearance(_ appearance: SidecarAppearance) {
        guard !stopped else { return }
        settings.appearance = appearance
        persistence?.save(settings)
    }
    public func selectBucket(id: String?) {
        settings.bucketID = id; persistence?.save(settings)
    }
    public func earlierRequests() { if page.hasEarlier { requestPage += 1 } }
    public func newerRequests() { if page.hasNewer { requestPage -= 1 } }
    public func refreshQuotas() async {
        guard !stopped, let runtime else { return }
        async let local: Void = runtime.reader.refresh()
        async let quotas: Void = runtime.quotas.refresh(now: Date())
        _ = await (local, quotas)
    }
    public func wake() async { await runtime?.quotas.wake() }
    public func setOffline(_ enabled: Bool) async {
        guard !stopped else { return }
        settings.offline = enabled; persistence?.save(settings)
        if enabled { quota = .unavailable(.offline) }
        await runtime?.quotas.setOffline(enabled)
    }
    public func applySettings(root: String, executable: String) async {
        guard !stopped else { return }
        func path(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let r = path(root), e = path(executable)
        guard r != settings.rootOverride || e != settings.executableOverride else { return }
        settings.rootOverride = r; settings.executableOverride = e
        settings.selectedID = nil; settings.bucketID = nil
        persistence?.save(settings)
        await replaceRuntime()
    }
    public func stop() async {
        guard !stopped else { return }
        stopped = true; generation += 1
        transition?.cancel()
        subscriptions.forEach { $0.cancel() }; subscriptions.removeAll()
        providerStart?.cancel()
        let old = runtime; runtime = nil
        await old?.stop()
        await providerStart?.value; providerStart = nil
        await transition?.value; transition = nil
    }
}
