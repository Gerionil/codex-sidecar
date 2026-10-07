import Foundation
import Dispatch
import Darwin

public struct SessionDescriptor: Equatable, Sendable {
    public let id: String
    public let sourceURLs: [URL]
    public let projectName: String?
    public let cliVersion: String?
    public let lastActivity: Date?
    public let parentThreadID: String?
    public let provenanceAmbiguous: Bool
    public init(id: String, sourceURLs: [URL], projectName: String?, cliVersion: String?,
                lastActivity: Date?, parentThreadID: String?, provenanceAmbiguous: Bool = false) {
        self.id = id; self.sourceURLs = sourceURLs; self.projectName = projectName
        self.cliVersion = cliVersion; self.lastActivity = lastActivity; self.parentThreadID = parentThreadID
        self.provenanceAmbiguous = provenanceAmbiguous
    }
}

/// An owned, read-only descriptor; signals only schedule reconciliation.
final class FileHint: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    init?(url: URL, signal: @escaping @Sendable () -> Void) {
        let fd = SourceAccess.descriptor(url, flags: O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke], queue: .global(qos: .utility))
        source.setEventHandler(handler: signal)
        source.setCancelHandler { close(fd) }
        source.resume()
    }
    deinit { source.cancel() }
}

/// Never follows symlink components. All opened sources must be regular files.
enum SourceAccess {
    static func openFile(_ url: URL) throws -> FileHandle {
        let fd = descriptor(url, flags: O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(fd); throw CocoaError(.fileReadNoPermission)
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    /// Parent directory descriptors pin the traversal, even if names are replaced concurrently.
    static func descriptor(_ url: URL, flags: Int32) -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else { return -1 }
        let components = url.path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(".."), !components.contains(".") else { return -1 }
        var parent = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { return -1 }
        for component in components.dropLast() {
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(parent)
            guard next >= 0 else { return -1 }
            parent = next
        }
        defer { close(parent) }
        return openat(parent, components.last!, flags | O_NOFOLLOW | O_CLOEXEC)
    }

}

public actor SessionCatalog {
    public enum Status: Sendable { case available, missingRoot, unreadableRoot, partial }
    public private(set) var lastStatus: Status = .available
    private let includeArchives: Bool
    private let watcherHints: Bool
    private var generation = 0
    private var worker: Task<Void, Never>?
    private var hints: [FileHint] = []
    private var subscriptions: [UUID: AsyncStream<[SessionDescriptor]>.Continuation] = [:]
    private var root: URL?
    private var scanSequence = 0
    private var publishSequence = 0
    private var scans: [UUID: Task<([SessionDescriptor], Status), Never>] = [:]
    public init(includeArchives: Bool = true, watcherHints: Bool = true) {
        self.includeArchives = includeArchives; self.watcherHints = watcherHints
    }
    public nonisolated static func resolveRoot(override: URL?, environment: [String: String], userHome: URL) -> URL {
        override ?? environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? userHome.appendingPathComponent(".codex", isDirectory: true)
    }
    public func discover(root: URL) async -> [SessionDescriptor] {
        scanSequence += 1
        let sequence = scanSequence, epoch = generation, id = UUID()
        let archives = includeArchives
        let task = Task.detached(priority: .utility) { Self.scan(root: root, includeArchives: archives) }
        scans[id] = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        scans.removeValue(forKey: id)
        if sequence == scanSequence, epoch == generation, !task.isCancelled { lastStatus = result.1 }
        return result.0
    }
    public func sessions(root: URL) -> AsyncStream<[SessionDescriptor]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[SessionDescriptor]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscriptions[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        if self.root != root || worker == nil {
            shutdown(); self.root = root
            let epoch = generation
            hints = (watcherHints ? [root, root.appendingPathComponent("sessions"), root.appendingPathComponent("archived_sessions")] : []).compactMap { url in
                FileHint(url: url) { [weak self] in Task { await self?.reconcile(epoch) } }
            }
            worker = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.reconcile(epoch)
                    do { try await Task.sleep(for: .seconds(5)) } catch { break }
                }
            }
        } else { Task { await reconcile(generation) } }
        return stream
    }
    private func reconcile(_ epoch: Int) async {
        guard epoch == generation, let root else { return }
        publishSequence += 1
        let sequence = publishSequence
        let sessions = await discover(root: root)
        guard epoch == generation, sequence == publishSequence, !Task.isCancelled else { return }
        for continuation in subscriptions.values { continuation.yield(sessions) }
    }
    private func unsubscribe(_ id: UUID) {
        guard subscriptions.removeValue(forKey: id) != nil else { return }
        if subscriptions.isEmpty { shutdown() }
    }
    private func shutdown() {
        generation += 1; scanSequence += 1; publishSequence += 1
        worker?.cancel(); worker = nil; hints.removeAll(); root = nil
        for task in scans.values { task.cancel() }
    }
    public func stop() async {
        shutdown()
        let pending = Array(scans.values)
        let continuations = subscriptions.values; subscriptions.removeAll()
        for continuation in continuations { continuation.finish() }
        for task in pending { _ = await task.value }
    }
    deinit { worker?.cancel(); for task in scans.values { task.cancel() } }

    private nonisolated static func scan(root: URL, includeArchives: Bool) -> ([SessionDescriptor], Status) {
        let fm = FileManager.default
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &directory) else { return ([], .missingRoot) }
        guard directory.boolValue, let attributes = try? fm.attributesOfItem(atPath: root.path),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o500 == 0o500,
              fm.isReadableFile(atPath: root.path) else { return ([], .unreadableRoot) }
        var groups: [String: [SessionDescriptor]] = [:]
        var status: Status = .available
        for folder in includeArchives ? ["sessions", "archived_sessions"] : ["sessions"] {
            let base = root.appendingPathComponent(folder)
            if !fm.fileExists(atPath: base.path) { continue }
            guard base.resolvingSymlinksInPath() == base,
                  let attrs = try? fm.attributesOfItem(atPath: base.path),
                  ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o500 == 0o500 else { status = .partial; continue }
            guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in status = .partial; return true }) else { status = .partial; continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { return ([], .partial) }
                guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]) else { status = .partial; continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true, url.pathExtension == "jsonl",
                      url.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { continue }
                do {
                    let handle = try SourceAccess.openFile(url); defer { try? handle.close() }
                    var framer = LineFramer()
                    var first: Data?
                    var invalidFrame = false
                    while first == nil {
                        if Task.isCancelled { return ([], .partial) }
                        let chunk = try handle.read(upToCount: 65536) ?? Data()
                        if chunk.isEmpty { break }
                        first = framer.append(chunk).first
                        if !framer.diagnostics.isEmpty { invalidFrame = true; break }
                    }
                    guard !invalidFrame, let first, case .header(let header) = RolloutDecoder().decodeLine(first,
                        at: .init(fileID: "catalog", byteOffset: 0)).event else { status = .partial; continue }
                    let project = try? JSONDecoder().decode(ProjectEnvelope.self, from: first).payload.cwd
                    let name = project.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
                    let attrs = try fm.attributesOfItem(atPath: url.path)
                    groups[header.threadID, default: []].append(.init(id: header.threadID, sourceURLs: [url], projectName: name,
                        cliVersion: header.cliVersion, lastActivity: attrs[.modificationDate] as? Date, parentThreadID: header.parentThreadID))
                } catch { status = .partial }
            }
        }
        let sessions = groups.map { id, copies in
            let first = copies[0]
            let parents = Set(copies.compactMap(\.parentThreadID))
            let ambiguous = copies.contains { $0.parentThreadID != first.parentThreadID }
            // Conflicting root/child provenance is conservatively excluded from root suggestions.
            return SessionDescriptor(id: id, sourceURLs: copies.flatMap(\.sourceURLs).sorted { $0.path < $1.path },
                projectName: copies.allSatisfy { $0.projectName == first.projectName } ? first.projectName : nil,
                cliVersion: copies.allSatisfy { $0.cliVersion == first.cliVersion } ? first.cliVersion : nil,
                lastActivity: copies.compactMap(\.lastActivity).max(),
                parentThreadID: ambiguous ? nil : parents.first, provenanceAmbiguous: ambiguous)
        }.sorted { lhs, rhs in
            let leftRoot = lhs.parentThreadID == nil && !lhs.provenanceAmbiguous
            let rightRoot = rhs.parentThreadID == nil && !rhs.provenanceAmbiguous
            return leftRoot != rightRoot ? leftRoot : lhs.id < rhs.id
        }
        return (sessions, status)
    }
}
private struct ProjectEnvelope: Decodable { let payload: ProjectPayload }
private struct ProjectPayload: Decodable { let cwd: String? }
