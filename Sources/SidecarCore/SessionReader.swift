import Foundation
import Darwin
import CryptoKit

public enum SourceAvailability: Sendable { case available, partial, unavailable }

/// One manually selected session. Only normalized contributions survive a read.
public actor SessionReader {
    private let root: URL?
    private let watcherHints: Bool
    private var selected: SessionDescriptor?
    private var generation = 0
    private var revision = 0
    private var sources: [URL: ReadContribution] = [:]
    private var snapshot: DerivedSession?
    private var subscriptions: [UUID: AsyncStream<DerivedSession>.Continuation] = [:]
    private var poller: Task<Void, Never>?
    private var catalogPoller: Task<Void, Never>?
    private var reading: Task<ReadBatch, Never>?
    private var readJobs: [UUID: Task<ReadBatch, Never>] = [:]
    private var hints: [FileHint] = []
    private var catalogHints: [FileHint] = []
    private var catalogDirty = false
    private var catalogWaiters: [CheckedContinuation<Void, Never>] = []
    private var catalogSequence = 0
    private var catalogRead: Task<[SessionDescriptor], Never>?
    private var dirty = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public init(root: URL? = nil, watcherHints: Bool = true) { self.root = root; self.watcherHints = watcherHints }
    public func currentSnapshot() -> DerivedSession? { snapshot }
    public var isReading: Bool { reading != nil }
    var workersRunning: Bool { poller != nil || catalogPoller != nil }

    public func snapshots() -> AsyncStream<DerivedSession> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<DerivedSession>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscriptions[id] = continuation
        if let snapshot { continuation.yield(snapshot) }
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        startWorkers()
        return stream
    }
    private func unsubscribe(_ id: UUID) {
        guard subscriptions.removeValue(forKey: id) != nil else { return }
        if subscriptions.isEmpty {
            generation += 1; revision += 1; catalogSequence += 1
            reading?.cancel(); reading = nil; catalogRead?.cancel(); catalogRead = nil
            finishWaiters(); cancelWorkers()
        }
    }
    public func select(_ session: SessionDescriptor) async {
        generation += 1; revision += 1; catalogSequence += 1
        catalogRead?.cancel(); catalogRead = nil
        finishWaiters()
        reading?.cancel(); reading = nil
        cancelWorkers()
        selected = session; sources.removeAll(); snapshot = nil
        startWorkers()
        await refresh()
    }
    private func startWorkers() {
        guard selected != nil, poller == nil else { return }
        let epoch = generation
        poller = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                await self?.refresh(epoch: epoch)
            }
        }
        if let root {
            catalogPoller = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { break }
                    await self?.reconcileCatalog(epoch: epoch)
                }
            }
            if watcherHints {
                catalogHints = [root, root.appendingPathComponent("sessions"), root.appendingPathComponent("archived_sessions")].compactMap { url in
                    FileHint(url: url) { [weak self] in Task { await self?.reconcileCatalog(epoch: epoch) } }
                }
            }
        }
        installFileHints(epoch)
    }
    private func installFileHints(_ epoch: Int) {
        hints.removeAll()
        guard watcherHints else { return }
        hints = (selected?.sourceURLs ?? []).compactMap { url in
            FileHint(url: url) { [weak self] in Task { await self?.refresh(epoch: epoch) } }
        }
    }
    private func cancelWorkers() {
        poller?.cancel(); poller = nil
        catalogPoller?.cancel(); catalogPoller = nil
        hints.removeAll(); catalogHints.removeAll()
    }
    private func refresh(epoch: Int) async {
        guard epoch == generation else { return }
        if reading != nil { dirty = true; return }
        await refresh()
    }
    public func refresh() async {
        guard let selected else { return }
        if reading != nil {
            dirty = true
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        let epoch = generation, version = revision, previous = sources
        dirty = false
        let task = Task.detached(priority: .utility) {
            Self.read(selected, previous: previous)
        }
        reading = task
        let jobID = UUID(); readJobs[jobID] = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        readJobs.removeValue(forKey: jobID)
        guard epoch == generation, version == revision else { return }
        reading = nil
        guard !task.isCancelled, !Task.isCancelled else { finishReadWaiters(); return }
        sources = result.sources
        if let state = result.snapshot, state != snapshot {
            snapshot = state
            for continuation in subscriptions.values { continuation.yield(state) }
        }
        if dirty { await refresh() }
        guard epoch == generation, version == revision else { return }
        finishReadWaiters()
    }
    public func reconcileCatalog() async {
        if catalogRead != nil {
            catalogDirty = true
            await withCheckedContinuation { catalogWaiters.append($0) }
            return
        }
        await reconcileCatalog(epoch: generation)
    }
    private func reconcileCatalog(epoch: Int) async {
        guard epoch == generation, let root, let id = selected?.id else { return }
        if catalogRead != nil { catalogDirty = true; return }
        catalogDirty = false
        catalogSequence += 1
        let sequence = catalogSequence
        let task = Task { await SessionCatalog().discover(root: root) }
        catalogRead = task
        let sessions = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard epoch == generation, sequence == catalogSequence else { return }
        guard !task.isCancelled, let current = selected else {
            catalogRead = nil; catalogDirty = false
            let pending = catalogWaiters; catalogWaiters.removeAll()
            for waiter in pending { waiter.resume() }
            return
        }
        let replacement = sessions.first { $0.id == id } ?? SessionDescriptor(id: id, sourceURLs: [],
            projectName: current.projectName, cliVersion: current.cliVersion, lastActivity: current.lastActivity, parentThreadID: current.parentThreadID)
        if replacement.sourceURLs != current.sourceURLs {
            revision += 1; reading?.cancel(); reading = nil
            selected = replacement
            installFileHints(epoch)
        }
        await refresh()
        guard epoch == generation, sequence == catalogSequence else { return }
        catalogRead = nil
        if catalogDirty { await reconcileCatalog(epoch: epoch) }
        let pending = catalogWaiters; catalogWaiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
    private func finishWaiters() {
        let scans = catalogWaiters; catalogWaiters.removeAll()
        for waiter in scans { waiter.resume() }
        finishReadWaiters()
    }
    private func finishReadWaiters() {
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
    public func stop() async {
        generation += 1; revision += 1; catalogSequence += 1
        let scan = catalogRead; scan?.cancel(); catalogRead = nil
        cancelWorkers(); finishWaiters()
        let tasks = Array(readJobs.values)
        for task in tasks { task.cancel() }
        reading = nil
        selected = nil; sources.removeAll(); snapshot = nil
        let continuations = subscriptions.values; subscriptions.removeAll()
        for continuation in continuations { continuation.finish() }
        for task in tasks { _ = await task.value }
        _ = await scan?.value
    }
    deinit { poller?.cancel(); catalogPoller?.cancel(); reading?.cancel(); catalogRead?.cancel(); for task in readJobs.values { task.cancel() } }

    private nonisolated static func read(_ session: SessionDescriptor, previous: [URL: ReadContribution]) -> ReadBatch {
        var contributions: [URL: ReadContribution] = [:]
        var extra: [SanitizedDiagnostic] = []
        var unavailable = 0
        var usedIDs = Set(previous.values.map(\.fileID))
        var nextID = 0
        for url in session.sourceURLs {
            if Task.isCancelled { return ReadBatch(sources: previous, snapshot: nil) }
            do {
                let handle = try SourceAccess.openFile(url)
                defer { try? handle.close() }
                let signature = try FileSignature(handle)
                while usedIDs.contains("source-\(nextID)") { nextID += 1 }
                var state = previous[url] ?? ReadContribution(fileID: "source-\(nextID)")
                usedIDs.insert(state.fileID)
                let prior = state.signature
                let prefix = try fingerprint(handle, offset: 0, count: min(Int(state.offset), 4096))
                let boundary = try fingerprint(handle, offset: max(0, state.offset - 4096), count: min(Int(state.offset), 4096))
                let sameFile = prior?.identity == signature.identity
                let sameBytes = prefix == state.prefix && boundary == state.boundary
                let unchanged = prior == signature && sameBytes
                if unchanged { contributions[url] = state; continue }
                let appendCandidate = sameFile && signature.size > state.offset && sameBytes
                let appendOnly = try appendCandidate && fullFingerprint(handle, count: state.offset) == state.digest
                if !appendOnly { state = ReadContribution(fileID: state.fileID) }
                try handle.seek(toOffset: UInt64(state.offset))
                // Read only the statted extent; a busy writer cannot make this loop unbounded.
                let target = signature.size
                while state.offset < target {
                    try Task.checkCancellation()
                    let chunk = try handle.read(upToCount: min(65536, Int(target - state.offset))) ?? Data()
                    if chunk.isEmpty { throw CocoaError(.fileReadUnknown) }
                    let lines = state.framer.append(chunk)
                    let frameDiagnostics = state.framer.takeDiagnostics()
                    let offsets = state.framer.completedOffsets
                    for (lineIndex, line) in lines.enumerated() {
                        if line.isEmpty { continue }
                        let decoded = RolloutDecoder().decodeLine(line,
                            at: .init(fileID: state.fileID, byteOffset: offsets[lineIndex]))
                        if state.headerStatus == .pending {
                            let oversizedBefore = frameDiagnostics.contains { ($0.byteOffset ?? 0) < offsets[lineIndex] }
                            if !oversizedBefore, case .header(let header) = decoded.event, header.threadID == session.id {
                                state.headerStatus = .valid
                            } else {
                                state.headerStatus = .invalid
                                state.add([.init(category: .invalidIdentity, byteOffset: offsets[lineIndex])])
                            }
                        }
                        if state.headerStatus == .valid, let event = decoded.event { state.events.append(event) }
                        state.add(decoded.diagnostics)
                    }
                    if state.headerStatus == .pending, !frameDiagnostics.isEmpty {
                        state.headerStatus = .invalid
                        state.add([.init(category: .invalidIdentity)])
                    }
                    state.add(frameDiagnostics)
                    state.offset += Int64(chunk.count)
                }
                state.digest = try fullFingerprint(handle, count: state.offset)
                let after = try FileSignature(handle)
                // Concurrent rewrite/replacement must not publish a mixed contribution.
                guard signature == after else { throw CocoaError(.fileReadUnknown) }
                state.signature = after
                state.prefix = try fingerprint(handle, offset: 0, count: min(Int(state.offset), 4096))
                state.boundary = try fingerprint(handle, offset: max(0, state.offset - 4096), count: min(Int(state.offset), 4096))
                contributions[url] = state
            } catch is CancellationError { return ReadBatch(sources: previous, snapshot: nil) }
            catch {
                unavailable += 1
                extra.append(.init(category: .sourceUnavailable))
            }
        }
        if session.sourceURLs.isEmpty { unavailable = 1; extra.append(.init(category: .sourceUnavailable)) }
        guard !Task.isCancelled else { return ReadBatch(sources: previous, snapshot: nil) }
        let ordered = session.sourceURLs.compactMap { contributions[$0] }
        for state in ordered {
            extra += state.diagnostics
            if state.framer.hasIncompleteLine { extra.append(.init(category: .incompleteRecord)) }
        }
        var derived = SessionReducer.reduce(ordered.flatMap(\.events), owningThreadID: session.id)
        guard !Task.isCancelled else { return ReadBatch(sources: previous, snapshot: nil) }
        if !extra.isEmpty { derived.reconciliation.status = .degraded }
        derived.diagnostics += extra
        derived.sourceAvailability = unavailable > 0 && contributions.isEmpty ? .unavailable
            : (extra.isEmpty ? .available : .partial)
        return ReadBatch(sources: contributions, snapshot: derived)
    }
    private nonisolated static func fullFingerprint(_ handle: FileHandle, count: Int64) throws -> [UInt8] {
        try handle.seek(toOffset: 0)
        var remaining = count
        var digest = SHA256()
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: min(65536, Int(remaining))) ?? Data()
            guard !data.isEmpty else { throw CocoaError(.fileReadUnknown) }
            digest.update(data: data); remaining -= Int64(data.count)
        }
        return Array(digest.finalize())
    }
    private nonisolated static func fingerprint(_ handle: FileHandle, offset: Int64, count: Int) throws -> UInt64 {
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: count) ?? Data()
        return data.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}

private struct ReadBatch: Sendable { let sources: [URL: ReadContribution]; let snapshot: DerivedSession? }
private struct ReadContribution: Sendable {
    let fileID: String
    var offset: Int64 = 0
    enum HeaderStatus: Sendable { case pending, valid, invalid }
    var headerStatus: HeaderStatus = .pending
    var digest: [UInt8] = []
    var signature: FileSignature?
    var prefix: UInt64 = 14695981039346656037
    var boundary: UInt64 = 14695981039346656037
    var framer = LineFramer()
    var events: [MetricEvent] = []
    var diagnostics: [SanitizedDiagnostic] = []
    mutating func add(_ new: [SanitizedDiagnostic]) {
        for diagnostic in new {
            if let index = diagnostics.firstIndex(where: { $0.category == diagnostic.category }) {
                let old = diagnostics[index]
                diagnostics[index] = .init(category: old.category, byteOffset: old.byteOffset,
                    occurrenceCount: old.occurrenceCount + diagnostic.occurrenceCount)
            } else { diagnostics.append(diagnostic) }
        }
    }
}
private struct FileSignature: Equatable, Sendable {
    let identity: String
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64
    init(_ handle: FileHandle) throws {
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
        identity = "\(info.st_dev):\(info.st_ino)"
        size = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec); modifiedNanos = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec); changedNanos = Int64(info.st_ctimespec.tv_nsec)
    }
}
