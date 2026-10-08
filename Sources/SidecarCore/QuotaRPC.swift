import Foundation
import Darwin

public protocol QuotaScheduler: Sendable {
    func now() -> Date
    func sleep(until deadline: Date) async throws
}
public struct SystemQuotaScheduler: QuotaScheduler {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(until deadline: Date) async throws {
        try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
    }
}
public protocol QuotaTransport: Sendable {
    func request(method: String, params: Data?) async throws -> Data
    func notifications() -> AsyncStream<Data>
    func stop() async
}

public struct QuotaProcessConfiguration: Sendable {
    public let executable: URL
    public let root: URL
    public let environment: [String: String]
    public let arguments = ["-c", "analytics.enabled=false", "app-server", "--listen", "stdio://"]
    public init(executable: URL, root: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = executable; self.root = root
        var env = environment; env["CODEX_HOME"] = root.path; self.environment = env
    }
}
public enum QuotaExecutable {
    public static let installedCandidates = [
        URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
        URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
    ]
    /// Discovery never executes a shell, resolves cwd-relative PATH entries, or reads credentials.
    /// Callers verify --version and capabilities before claiming compatibility.
    public static func resolve(override: URL?, environment: [String: String], bundleCandidates: [URL] = installedCandidates) -> URL? {
        if let override { return valid(override) ? override : nil }
        let path = (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }
        let candidates = path.map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") } + bundleCandidates
        return candidates.first(where: valid)
    }
    private static func valid(_ url: URL) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { return false }
        return true
    }
}

enum QuotaWireEvent: Sendable { case stdout(Data), exited, overflow }
protocol QuotaWire: Sendable {
    var events: AsyncStream<QuotaWireEvent> { get }
    func start() async throws
    func write(_ bytes: Data) async throws
    func stop() async
}

/// Every process, pipe and read worker belongs to this client. Stderr is discarded on arrival.
/// Nonblocking dispatch sources drain both pipes, independent of the actor and RPC requests.
final class ProcessQuotaWire: QuotaWire, @unchecked Sendable {
    let events: AsyncStream<QuotaWireEvent>
    private let continuation: AsyncStream<QuotaWireEvent>.Continuation
    private let config: QuotaProcessConfiguration
    private let queue = DispatchQueue(label: "Sidecar.quota.io", qos: .utility)
    private var process: Process?
    private var input: FileHandle?
    private var sources: [DispatchSourceRead] = []
    private var ended = false
    private var writer: DispatchSourceWrite?
    private struct WriteJob { var bytes: Data; var offset = 0; let completion: CheckedContinuation<Void, Error> }
    private var writes: [WriteJob] = []
    init(_ config: QuotaProcessConfiguration) {
        self.config = config
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingOldest(64))
    }
    func start() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard !ended else { c.resume(throwing: QuotaFailure.stopped); return }
                if process != nil { c.resume(); return }
                guard FileManager.default.isExecutableFile(atPath: config.executable.path) else {
                    c.resume(throwing: QuotaFailure.missingExecutable); return
                }
                let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                p.executableURL = config.executable; p.arguments = config.arguments; p.environment = config.environment
                p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
                p.terminationHandler = { [weak self] _ in
                    guard let self else { return }
                    self.queue.async { self.continuation.yield(.exited) }
                }
                do {
                    try p.run(); process = p; input = stdin.fileHandleForWriting
                    let fd = stdin.fileHandleForWriting.fileDescriptor
                    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
                    _ = fcntl(fd, F_SETNOSIGPIPE, 1)
                    drain(stdout.fileHandleForReading, stdout: true)
                    drain(stderr.fileHandleForReading, stdout: false)
                    c.resume()
                } catch { c.resume(throwing: QuotaFailure.processExited) }
            }
        }
    }
    private func drain(_ handle: FileHandle, stdout: Bool) {
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            // Bound one turn so stderr/exit/stop cannot be starved by continuous stdout.
            for _ in 0..<16 {
                let n = Darwin.read(fd, &buffer, buffer.count)
                if n > 0 {
                    if stdout {
                        if case .dropped = self.continuation.yield(.stdout(Data(buffer.prefix(n)))) {
                            self.continuation.yield(.overflow)
                            self.process?.terminate(); source?.cancel(); return
                        }
                    }
                } else if n == 0 { source?.cancel(); return }
                else if errno == EAGAIN || errno == EWOULDBLOCK { return }
                else { source?.cancel(); return }
            }
        }
        source.setCancelHandler { try? handle.close() }
        sources.append(source); source.resume()
    }
    func write(_ bytes: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard !ended, let input, process?.isRunning == true else { c.resume(throwing: QuotaFailure.processExited); return }
                guard bytes.count <= 1024, writes.count < 32 else { c.resume(throwing: QuotaFailure.malformedReply); return }
                writes.append(.init(bytes: bytes, completion: c))
                flushWrites(fd: input.fileDescriptor)
            }
        }
    }
    private func flushWrites(fd: Int32) {
        guard !ended else { return }
        while !writes.isEmpty {
            let job = writes[0]
            let n = job.bytes.withUnsafeBytes { pointer in
                Darwin.write(fd, pointer.baseAddress!.advanced(by: job.offset), job.bytes.count - job.offset)
            }
            if n > 0 {
                writes[0].offset += n
                if writes[0].offset == writes[0].bytes.count { writes.removeFirst().completion.resume() }
            } else if n < 0, errno == EINTR { continue }
            else if n < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                if writer == nil {
                    let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
                    source.setEventHandler { [weak self] in self?.flushWrites(fd: fd) }
                    writer = source; source.resume()
                }
                return
            } else {
                failWrites(.processExited); return
            }
        }
        writer?.cancel(); writer = nil
    }
    private func failWrites(_ reason: QuotaFailure) {
        writer?.cancel(); writer = nil
        let pending = writes; writes.removeAll()
        for job in pending { job.completion.resume(throwing: reason) }
    }
    func stop() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if ended { c.resume(); return }
                ended = true
                failWrites(.stopped)
                try? input?.close(); input = nil
                for source in sources { source.cancel() }; sources.removeAll()
                let owned = process; process = nil
                if let owned, owned.isRunning {
                    owned.terminate()
                    // Bound termination grace; SIGKILL is restricted to the still-owned running child.
                    DispatchQueue.global(qos: .utility).async {
                        let deadline = Date().addingTimeInterval(1)
                        while owned.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
                        if owned.isRunning { kill(owned.processIdentifier, SIGKILL) }
                        owned.waitUntilExit(); c.resume()
                    }
                } else { c.resume() }
                continuation.finish()
            }
        }
    }
    deinit {
        writer?.cancel()
        for job in writes { job.completion.resume(throwing: QuotaFailure.stopped) }
        for source in sources { source.cancel() }
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        continuation.finish()
    }
}

public actor QuotaRPC: QuotaTransport {
    private let wire: any QuotaWire
    private let scheduler: any QuotaScheduler
    private nonisolated let notificationStream: AsyncStream<Data>
    private let notificationContinuation: AsyncStream<Data>.Continuation
    private var reader: Task<Void, Never>?
    private var starting: Task<Void, Error>?
    private var started = false
    private var stopped = false
    private var nextID = 0
    private var buffer = Data()
    private var accountHintPending = false
    private struct Pending { let continuation: CheckedContinuation<Data, Error>; let timer: Task<Void, Never> }
    private var pending: [Int: Pending] = [:]
    public init(configuration: QuotaProcessConfiguration, scheduler: any QuotaScheduler = SystemQuotaScheduler()) {
        wire = ProcessQuotaWire(configuration); self.scheduler = scheduler
        (notificationStream, notificationContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }
    init(wire: any QuotaWire, scheduler: any QuotaScheduler = SystemQuotaScheduler()) {
        self.wire = wire; self.scheduler = scheduler
        (notificationStream, notificationContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }
    public nonisolated func notifications() -> AsyncStream<Data> { notificationStream }
    public func request(method: String, params: Data?) async throws -> Data {
        let value = try Self.allowedParams(method, params)
        if method == "account/read" { accountHintPending = false }
        guard !stopped else { throw QuotaFailure.stopped }
        if !started {
            if starting == nil {
                let wire = wire
                starting = Task { try await wire.start() }
                let events = wire.events
                reader = Task { [weak self] in
                    for await event in events { await self?.receive(event) }
                    await self?.end(.processExited)
                }
            }
            do { try await starting!.value } catch { await end(error as? QuotaFailure ?? .processExited); throw error as? QuotaFailure ?? .processExited }
            guard !stopped else { throw QuotaFailure.stopped }
            started = true; starting = nil
        }
        try Task.checkCancellation()
        nextID += 1; let id = nextID
        var packet: [String: Any] = ["method": method, "params": value]
        if method != "initialized" { packet["id"] = id }
        var bytes = try JSONSerialization.data(withJSONObject: packet); bytes.append(10)
        if method == "initialized" { try await wire.write(bytes); return Data("{}".utf8) }
        let requestBytes = bytes
        let deadline = scheduler.now().addingTimeInterval(20)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self, scheduler] in
                    do { try await scheduler.sleep(until: deadline) } catch { return }
                    await self?.fail(id, .timeout)
                }
                pending[id] = Pending(continuation: continuation, timer: timer)
                Task { [weak self, wire] in
                    do { try await wire.write(requestBytes) }
                    catch { await self?.fail(id, error as? QuotaFailure ?? .processExited) }
                }
                if Task.isCancelled { fail(id, .cancelled) }
            }
        } onCancel: { Task { await self.fail(id, .cancelled) } }
    }
    private static func allowedParams(_ method: String, _ params: Data?) throws -> [String: Any] {
        let value = try params.map(QuotaDecoder.dictionary) ?? [:]
        switch method {
        case "initialize":
            guard let client = value["clientInfo"] as? [String: Any], client["name"] as? String == "codex_sidecar",
                  client["version"] as? String == "0.1.0", Set(client.keys) == ["name", "version"],
                  Set(value.keys) == ["clientInfo"] else { throw QuotaFailure.unsupportedProtocol }
        case "initialized": guard value.isEmpty else { throw QuotaFailure.unsupportedProtocol }
        case "account/read": guard Set(value.keys) == ["refreshToken"], QuotaDecoder.boolean(value["refreshToken"]) == false else { throw QuotaFailure.unsupportedProtocol }
        case "account/rateLimits/read": guard Set(value.keys) == ["excludeResetCreditDetails"], QuotaDecoder.boolean(value["excludeResetCreditDetails"]) == true else { throw QuotaFailure.unsupportedProtocol }
        default: throw QuotaFailure.unsupportedProtocol
        }
        return value
    }
    private func receive(_ event: QuotaWireEvent) async {
        guard !stopped else { return }
        switch event {
        case .exited: await end(.processExited)
        case .overflow: await end(.malformedReply)
        case .stdout(let data):
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                do { try await receiveLine(line) } catch { await end(.malformedReply); return }
                if stopped { return }
            }
            if buffer.count > 1024 * 1024 { await end(.malformedReply) }
        }
    }
    private func receiveLine(_ line: Data) async throws {
        let packet = try QuotaDecoder.dictionary(line)
        if let method = packet["method"] as? String {
            if let id = packet["id"], !(id is NSNull) {
                guard (id as? String).map({ $0.utf8.count <= 256 }) == true || QuotaDecoder.integer(id) != nil else { throw QuotaFailure.malformedReply }
                let response: [String: Any] = ["id": id, "error": ["code": -32601, "message": "Unsupported method"]]
                var data = try JSONSerialization.data(withJSONObject: response); data.append(10)
                try await wire.write(data)
            } else if method == "account/rateLimits/updated" || method == "account/updated" {
                // Only method survives: notification payloads are refresh hints, not cache/account values.
                if method == "account/updated" { accountHintPending = true }
                notificationContinuation.yield(try JSONSerialization.data(withJSONObject: ["method": accountHintPending ? "account/updated" : method]))
            }
            return
        }
        guard let n = QuotaDecoder.integer(packet["id"]), n >= 0, n <= Int.max else { throw QuotaFailure.malformedReply }
        let id = Int(n)
        guard let item = pending.removeValue(forKey: id) else { return } // cancelled or obsolete request
        item.timer.cancel()
        if packet["error"] != nil { item.continuation.resume(throwing: QuotaFailure.requestFailed) }
        else if let result = packet["result"] as? [String: Any] {
            item.continuation.resume(returning: try JSONSerialization.data(withJSONObject: result))
        } else { item.continuation.resume(throwing: QuotaFailure.malformedReply) }
    }
    private func fail(_ id: Int, _ reason: QuotaFailure) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timer.cancel(); item.continuation.resume(throwing: reason)
    }
    private func end(_ reason: QuotaFailure) async {
        guard !stopped else { return }
        stopped = true; buffer.removeAll(); reader?.cancel(); reader = nil; starting?.cancel(); starting = nil
        for id in Array(pending.keys) { fail(id, reason) }
        notificationContinuation.finish(); await wire.stop()
    }
    public func stop() async { await end(.stopped) }
    deinit { reader?.cancel(); starting?.cancel(); for item in pending.values { item.timer.cancel(); item.continuation.resume(throwing: QuotaFailure.stopped) }; notificationContinuation.finish() }
}
