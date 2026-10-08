import Foundation

/// Independent current-account state. Never consumes a selected chat or session metrics.
public actor QuotaProvider {
    public typealias TransportFactory = @Sendable () async throws -> any QuotaTransport
    private let scheduler: any QuotaScheduler
    private let factory: TransportFactory
    private var offline: Bool
    private var stopped = false
    private var running = false
    private var generation: UInt64 = 0
    private var transport: (any QuotaTransport)?
    private var initialized = false
    private var identity: String? // transient; never exposed in state or diagnostics
    private var quotaAccountID: String? // transient workspace/account change evidence
    private var state: QuotaState
    private var flight: Task<Void, Never>?
    private var flightID: UUID?
    private var processID: UUID?
    public var isRefreshing: Bool { flight != nil }
    private var timer: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    private var nextRead: Date?
    private var failures = 0
    private var resetHints: Set<Date> = []
    private var subscriptions: [UUID: AsyncStream<QuotaState>.Continuation] = [:]

    public init(offline: Bool = false, scheduler: any QuotaScheduler = SystemQuotaScheduler(), transportFactory: @escaping TransportFactory) {
        self.offline = offline; self.scheduler = scheduler; factory = transportFactory
        state = offline ? .unavailable(.offline) : .loading
    }
    public init(configuration: QuotaProcessConfiguration, offline: Bool = false, scheduler: any QuotaScheduler = SystemQuotaScheduler()) {
        self.offline = offline; self.scheduler = scheduler
        factory = { QuotaRPC(configuration: configuration, scheduler: scheduler) }
        state = offline ? .unavailable(.offline) : .loading
    }
    public func currentState() -> QuotaState { state }
    public func snapshots() -> AsyncStream<QuotaState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<QuotaState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard !stopped else { continuation.finish(); return stream }
        subscriptions[id] = continuation; continuation.yield(state)
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream
    }
    private func unsubscribe(_ id: UUID) async {
        guard subscriptions.removeValue(forKey: id) != nil else { return }
        if subscriptions.isEmpty { await suspend() }
    }
    private func publish(_ new: QuotaState) {
        state = new
        for continuation in subscriptions.values { continuation.yield(new) }
    }
    public func start() async {
        guard !stopped, !offline else { return }
        running = true
        await refresh(now: scheduler.now())
    }
    public func refresh(now: Date) async {
        await refresh(now: now, recoverInvalidatedRead: true)
    }
    private func refresh(now: Date, recoverInvalidatedRead: Bool) async {
        guard !stopped, !offline else { return }
        running = true
        if let flight { await flight.value; return }
        let epoch = generation
        nextRead = now.addingTimeInterval(60)
        let id = UUID()
        let task = Task<Void, Never> { [weak self] in await self?.read(epoch: epoch) }
        flight = task; flightID = id
        reschedule()
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        guard flightID == id else { return }
        flight = nil; flightID = nil
        // A startup account hint can invalidate a pending read without replacing
        // its process. Recover once immediately; repeated hints fall back to polling.
        if recoverInvalidatedRead, epoch != generation, running, !offline, !stopped, !Task.isCancelled,
           case .loading = state {
            await refresh(now: scheduler.now(), recoverInvalidatedRead: false)
            return
        }
        reschedule()
    }
    private func read(epoch: UInt64) async {
        var operationEpoch = epoch
        do {
            if transport == nil {
                let created = try await factory()
                guard epoch == generation, !offline, !stopped, !Task.isCancelled else { await created.stop(); return }
                transport = created
                let stream = created.notifications()
                let processToken = UUID(); processID = processToken
                listener = Task { [weak self] in
                    for await bytes in stream {
                        if Task.isCancelled { break }
                        await self?.notification(bytes, processToken: processToken)
                    }
                }
            }
            guard let transport else { return }
            let ownedProcess = processID
            if !initialized {
                let reply: Data
                do { reply = try await transport.request(method: "initialize", params: Data(#"{"clientInfo":{"name":"codex_sidecar","version":"0.1.0"}}"#.utf8)) }
                catch { throw (error as? QuotaFailure == .requestFailed ? QuotaFailure.unsupportedProtocol : error) }
                guard ownedProcess == processID, !offline, !stopped else { return }
                let initResult = try QuotaDecoder.dictionary(reply)
                guard let agent = initResult["userAgent"] as? String, !agent.isEmpty else { throw QuotaFailure.unsupportedProtocol }
                _ = try await transport.request(method: "initialized", params: nil)
                guard ownedProcess == processID, !offline, !stopped else { return }
                initialized = true
            }
            guard valid(epoch) else { return }
            let accountBytes = try await transport.request(method: "account/read", params: Data(#"{"refreshToken":false}"#.utf8))
            guard valid(epoch) else { return }
            let accountReply = try QuotaDecoder.dictionary(accountBytes)
            guard accountReply.keys.contains("account") else { throw QuotaFailure.authenticationAbsent }
            guard let account = accountReply["account"] as? [String: Any] else {
                if accountReply["account"] is NSNull { throw QuotaFailure.authenticationAbsent }
                throw QuotaFailure.malformedReply
            }
            guard let kind = account["type"] as? String else { throw QuotaFailure.malformedReply }
            if kind == "apiKey" { throw QuotaFailure.apiKeyOnly }
            guard kind == "chatgpt" else { throw QuotaFailure.unsupportedProtocol }
            // Only compare allowlisted identity fields, never serialize or export the account payload.
            let fingerprint = [kind, account["email"] as? String ?? "", account["chatgptAccountId"] as? String ?? ""].joined(separator: "\u{0}")
            if let identity, identity != fingerprint {
                // Invalidate old values before awaiting the new account's quota response.
                generation &+= 1; self.identity = fingerprint; quotaAccountID = nil; resetHints.removeAll()
                publish(.loading)
                operationEpoch = generation
            } else { identity = fingerprint }
            let readEpoch = generation
            let quotaBytes = try await transport.request(method: "account/rateLimits/read", params: Data(#"{"excludeResetCreditDetails":true}"#.utf8))
            guard valid(readEpoch) else { return }
            let raw = try QuotaDecoder.dictionary(quotaBytes)
            if let accountID = raw["accountId"] as? String {
                if let prior = quotaAccountID, prior != accountID { generation &+= 1; operationEpoch = generation; resetHints.removeAll(); publish(.loading) }
                quotaAccountID = accountID
            }
            let snapshot = try QuotaDecoder.decodeRead(quotaBytes, receivedAt: scheduler.now()).stamped(generation: generation)
            guard !Task.isCancelled else { return }
            failures = 0; nextRead = scheduler.now().addingTimeInterval(60)
            publish(.available(snapshot))
            // Already-past resets stay awaiting refresh; retry at the ordinary poll, never loop immediately.
            if snapshot.buckets.flatMap(\.windows).contains(where: { ($0.resetAt ?? .distantFuture) <= scheduler.now() }) {
                for date in snapshot.buckets.flatMap(\.windows).compactMap(\.resetAt) where date <= scheduler.now() { resetHints.insert(date) }
                publish(.stale(snapshot, .resetPassed))
            }
        } catch {
            guard valid(operationEpoch) else { return }
            let reason = error as? QuotaFailure ?? (error is CancellationError ? .cancelled : .requestFailed)
            if reason == .authenticationAbsent || reason == .apiKeyOnly {
                generation &+= 1; identity = nil; quotaAccountID = nil; resetHints.removeAll()
                publish(.unavailable(reason))
            } else if let last = state.lastGood { publish(.error(reason, last)) }
            else { publish(.unavailable(reason)) }
            failures += 1
            nextRead = scheduler.now().addingTimeInterval([60.0, 120, 300][min(failures - 1, 2)])
            if [.processExited, .timeout, .malformedReply, .unsupportedProtocol, .stopped].contains(reason) {
                let old = self.transport; self.transport = nil; processID = nil; initialized = false; listener?.cancel(); listener = nil
                await old?.stop()
            }
        }
    }
    private func valid(_ epoch: UInt64) -> Bool { epoch == generation && !offline && !stopped && running && !Task.isCancelled }
    private func notification(_ data: Data, processToken: UUID) async {
        guard processToken == processID, !offline, !stopped, running,
              let raw = try? QuotaDecoder.dictionary(data), let method = raw["method"] as? String else { return }
        if method == "account/updated" {
            // Keep the process/handshake; startup notifications must not cause a restart loop.
            generation &+= 1; identity = nil; quotaAccountID = nil; resetHints.removeAll()
            publish(.loading)
            nextRead = scheduler.now().addingTimeInterval(60)
            reschedule()
        }
        // Rate notifications deliberately change neither cache nor deadlines: next eligible full read coalesces them.
    }
    private func reschedule() {
        timer?.cancel(); timer = nil
        guard running, !offline, !stopped else { return }
        let now = scheduler.now()
        var dates: [Date] = []
        if flight == nil, let nextRead { dates.append(nextRead) }
        if let good = state.lastGood {
            let staleAt = good.receivedAt.addingTimeInterval(120)
            if case .available = state, staleAt > now { dates.append(staleAt) }
            dates += good.buckets.flatMap(\.windows).compactMap(\.resetAt).filter { $0 > now && !resetHints.contains($0) }
        }
        guard let deadline = dates.min() else { return }
        let epoch = generation
        timer = Task { [weak self, scheduler] in
            do { try await scheduler.sleep(until: deadline) } catch { return }
            await self?.tick(epoch: epoch)
        }
    }
    private func tick(epoch: UInt64) async {
        guard epoch == generation, running, !offline, !stopped else { return }
        let now = scheduler.now()
        var resetDue = false
        if let good = state.lastGood {
            let resets = good.buckets.flatMap(\.windows).compactMap(\.resetAt).filter { $0 <= now && !resetHints.contains($0) }
            if !resets.isEmpty {
                resetHints.formUnion(resets); resetDue = true; publish(.stale(good, .resetPassed))
            } else if now.timeIntervalSince(good.receivedAt) >= 120, case .available = state { publish(.stale(good, .age)) }
        }
        if flight == nil, resetDue || (nextRead ?? .distantFuture) <= now {
            Task { [weak self] in await self?.refresh(now: now) }
        } else { reschedule() }
    }
    public func wake() async {
        guard !stopped, !offline else { return }
        if let good = state.lastGood { publish(.stale(good, .wake)) }
        await refresh(now: scheduler.now())
    }
    public func accountChanged() async {
        guard !stopped else { return }
        publish(offline ? .unavailable(.offline) : .loading)
        let token = await invalidate()
        guard token == generation, !stopped, !offline else { return }
        await start()
    }
    public func setOffline(_ enabled: Bool) async {
        guard !stopped, offline != enabled else { return }
        offline = enabled
        publish(enabled ? .unavailable(.offline) : .loading)
        if enabled { running = false }
        let token = await invalidate()
        guard token == generation, !stopped, offline == enabled else { return }
        if !enabled { await start() }
    }
    @discardableResult private func invalidate() async -> UInt64 {
        generation &+= 1
        let token = generation
        flight?.cancel(); flight = nil; flightID = nil; processID = nil; timer?.cancel(); timer = nil; listener?.cancel(); listener = nil
        identity = nil; quotaAccountID = nil; initialized = false; failures = 0; resetHints.removeAll(); nextRead = nil
        let old = transport; transport = nil
        await old?.stop()
        return token
    }
    private func suspend() async {
        running = false; publish(offline ? .unavailable(.offline) : .unavailable(.stopped)); await invalidate()
    }
    public func stop() async {
        guard !stopped else { return }
        stopped = true; running = false; state = .unavailable(.stopped); await invalidate()
        let streams = subscriptions.values; subscriptions.removeAll()
        for stream in streams { stream.finish() }
    }
    deinit { flight?.cancel(); timer?.cancel(); listener?.cancel(); for stream in subscriptions.values { stream.finish() } }
}
