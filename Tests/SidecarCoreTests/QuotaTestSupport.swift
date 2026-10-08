import Foundation
import XCTest
@testable import SidecarCore

/// Test time advances only when the test explicitly moves it.
final class QuotaTestClock: QuotaScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1799999000)
    private var waits: [UUID: (Date, CheckedContinuation<Void, Error>)] = [:]
    private var cancelled: Set<UUID> = []
    func now() -> Date { lock.withLock { time } }
    func sleep(until deadline: Date) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock()
                if cancelled.remove(id) != nil || Task.isCancelled { lock.unlock(); c.resume(throwing: CancellationError()); return }
                if deadline <= time { lock.unlock(); c.resume(); return }
                waits[id] = (deadline, c); lock.unlock()
            }
        } onCancel: {
            self.lock.lock()
            let c = self.waits.removeValue(forKey: id)?.1
            if c == nil { self.cancelled.insert(id) }
            self.lock.unlock(); c?.resume(throwing: CancellationError())
        }
    }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); time.addTimeInterval(seconds)
        let due = waits.filter { $0.value.0 <= time }
        for id in due.keys { waits.removeValue(forKey: id) }
        lock.unlock()
        for (_, value) in due { value.1.resume() }
    }
    var sleepers: Int { lock.withLock { waits.count } }
}
func quotaEventually(_ condition: @escaping () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    // Bounded cooperative scheduling, no real sleeps or account access.
    for _ in 0..<20000 { if await condition() { return }; await Task.yield() }
    XCTFail("Condition did not become true", file: file, line: line)
}
func quotaBytes(_ value: String) -> Data { Data(value.utf8) }

actor QuotaTransportFake: QuotaTransport {
    nonisolated let stream: AsyncStream<Data>
    nonisolated let continuation: AsyncStream<Data>.Continuation
    var calls: [String] = []
    var stopped = 0
    var quota: Data
    var account = quotaBytes(#"{"account":{"type":"chatgpt","email":"synthetic-a@example.invalid"},"requiresOpenaiAuth":true}"#)
    var failure: QuotaFailure?
    var hold = false
    var waiting: CheckedContinuation<Data, Error>?
    var active = 0; var maximumActive = 0
    init(quota: Data) {
        self.quota = quota
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
    }
    func request(method: String, params: Data?) async throws -> Data {
        calls.append(method); active += 1; maximumActive = max(active, maximumActive)
        defer { active -= 1 }
        if method == "initialize" { return quotaBytes(#"{"userAgent":"synthetic"}"#) }
        if method == "initialized" { return quotaBytes("{}") }
        if method == "account/read" { return account }
        if hold { return try await withCheckedThrowingContinuation { waiting = $0 } }
        if let failure { throw failure }
        return quota
    }
    nonisolated func notifications() -> AsyncStream<Data> { stream }
    func stop() async { stopped += 1; continuation.finish() }
    func configure(hold: Bool = false, failure: QuotaFailure? = nil, account: Data? = nil, quota: Data? = nil) {
        self.hold = hold; self.failure = failure
        if let account { self.account = account }; if let quota { self.quota = quota }
    }
    func complete() { let c = waiting; waiting = nil; c?.resume(returning: quota) }
    func hint(_ method: String) { continuation.yield(quotaBytes("{\"method\":\"\(method)\",\"params\":{\"rateLimits\":{\"limitName\":null}}}")) }
    var reads: Int { calls.filter { $0 == "account/rateLimits/read" }.count }
}
actor QuotaFactoryFake {
    let transports: [QuotaTransportFake]
    var count = 0
    init(_ transports: [QuotaTransportFake]) { self.transports = transports }
    func make() throws -> any QuotaTransport {
        defer { count += 1 }
        return transports[min(count, transports.count - 1)]
    }
}
