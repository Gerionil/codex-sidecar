import XCTest
@testable import SidecarCore

@MainActor
final class PresentationStateTests: XCTestCase {
    func testPartialHistoryAndMissingCacheRemainExplicit() throws {
        let partial = try session("positive-baseline")
        let p = SessionPresentation(partial)
        XCTAssertEqual(p.reconciliation, "Partial history")
        XCTAssertEqual(p.currentContext, "Unavailable — exact current usage has no validated source")
        let missing = SessionPresentation(try session("partial-native-usage"))
        XCTAssertEqual(missing.cacheRate, "Unavailable")
        XCTAssertFalse(missing.configuredModel.contains("Actual model"))
    }
    func testInterruptedTaskDoesNotBecomeZeroRequest() throws {
        let p = SessionPresentation(try session("interrupted-no-usage"))
        XCTAssertEqual(p.observedTotal, "Unavailable")
        XCTAssertTrue(p.taskActivity.contains { $0.contains("Interrupted") && $0.contains("Usage not reported") })
    }
    func testConfiguredModelWithoutWindowOrExactContext() throws {
        let events = try Fixture.events("native-two-requests").filter {
            if case .header = $0 { return true }; if case .configuredModel = $0 { return true }; return false
        }
        let p = SessionPresentation(SessionReducer.reduce(events, owningThreadID: Fixture.threadID))
        XCTAssertTrue(p.configuredModel.contains("example-model"))
        XCTAssertEqual(p.window, "Unavailable")
        XCTAssertTrue(p.currentContext.contains("Unavailable"))
    }
    func testQuotaMappingRetainsWindowsAndFailureState() throws {
        let s = try QuotaDecoder.decodeRead(Fixture.data("weekly-only", ext: "json"), receivedAt: Date())
        let p = QuotaPresentation(.error(.timeout, s), bucketID: "codex")
        XCTAssertEqual(p.windows.count, 1)
        XCTAssertEqual(p.windows.first?.label, "Weekly")
        XCTAssertEqual(p.windows.first?.remaining, "75% remaining")
        XCTAssertTrue(p.status.contains("Error")); XCTAssertTrue(p.status.contains("stale"))
        XCTAssertTrue(QuotaPresentation(.stale(s, .wake), bucketID: "codex").status.contains("Stale"))
        let unknown = try QuotaDecoder.decodeRead(Data(#"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":null}}}}"#.utf8), receivedAt: Date())
        XCTAssertTrue(QuotaPresentation(.available(unknown), bucketID: nil).windows.isEmpty)
        let u = QuotaPresentation(.available(unknown), bucketID: "other")
        XCTAssertEqual(u.windows.first?.remaining, "Unavailable")
        XCTAssertEqual(u.windows.first?.label, "Unknown window")
    }
    func testDuplicateDurationsAndIndependentBucketChoice() throws {
        let raw = Data(#"{"rateLimitsByLimitId":{"a":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":null,"windowDurationMins":300}},"b":{"primary":{"usedPercent":40,"windowDurationMins":10080}}}}"#.utf8)
        let s = try QuotaDecoder.decodeRead(raw, receivedAt: Date())
        let a = QuotaPresentation(.available(s), bucketID: "a")
        XCTAssertEqual(a.windows.map(\.label), ["5h (primary)", "5h (secondary)"])
        XCTAssertEqual(a.windows.map(\.remaining), ["80% remaining", "Unavailable"])
        XCTAssertEqual(QuotaPresentation(.available(s), bucketID: "b").windows.map(\.label), ["Weekly"])
    }
    func testSelectionFromBothSurfacesPreservesQuotasAndRejectsLateA() async throws {
        let f = try Harness()
        await f.store.start()
        await f.catalog.send([f.a, f.b])
        await eventually { f.store.sessions.count == 2 }
        await f.store.selectSession(id: f.a.id)
        await f.reader.send(f.stateA)
        await eventually { f.store.session?.totals.total == 180 }
        await f.quota.send(.available(f.quotaSnapshot))
        await eventually { f.store.quota.lastGood != nil }
        // Both native selectors invoke the same command on this shared store.
        await f.store.selectSession(id: f.b.id)
        await f.reader.send(f.stateB)
        await eventually { f.store.session?.totals.total == 240 }
        await f.reader.send(f.stateA)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(f.store.selectedID, f.b.id)
        XCTAssertEqual(f.store.session?.requests.count, 2)
        XCTAssertEqual(f.store.session?.totals.total, 240)
        XCTAssertEqual(f.store.quota.lastGood, f.quotaSnapshot)
        await f.store.selectSession(id: f.a.id)
        await f.reader.send(f.stateA)
        await eventually { f.store.session?.totals.total == 180 }
        XCTAssertEqual(f.store.quota.lastGood, f.quotaSnapshot)
        await f.store.stop()
    }
    func testPinnedSelectionSurvivesNewChildrenAndSurfaceReopens() async throws {
        let f = try Harness()
        await f.store.start(); await f.catalog.send([f.a, f.b])
        await eventually { f.store.sessions.count == 2 }
        await f.store.selectSession(id: f.a.id)
        // Repeated application start is harmless; surfaces do not own subscriptions.
        await f.store.start(); await f.store.start()
        await f.catalog.send([f.b])
        await eventually { f.store.sessions.count == 1 }
        XCTAssertEqual(f.store.selectedID, f.a.id)
        let starts = await f.quota.starts
        let subscriptions = await f.reader.subscriptions
        XCTAssertEqual(starts, 1); XCTAssertEqual(subscriptions, 1)
        await f.store.stop()
        let stops = await f.quota.stops
        let readerStops = await f.reader.stops
        let catalogStops = await f.catalog.stops
        XCTAssertEqual(stops, 1); XCTAssertEqual(readerStops, 1); XCTAssertEqual(catalogStops, 1)
    }
    func testOfflineLeavesLocalUpdatesAndEmptySelectionHonest() async throws {
        let f = try Harness()
        await f.store.start()
        XCTAssertNil(f.store.selectedID); XCTAssertNil(f.store.session)
        await f.catalog.send([f.a]); await eventually { !f.store.sessions.isEmpty }
        await f.store.selectSession(id: f.a.id)
        await f.store.setOffline(true)
        await f.reader.send(f.stateA)
        await eventually { f.store.session?.totals.total == 180 }
        XCTAssertEqual(f.store.quota, .unavailable(.offline))
        let offline = await f.quota.offline
        XCTAssertTrue(offline)
        await f.store.stop()
    }
    func testNoRootAndEmptyCatalogHaveVisibleStates() async throws {
        let f = try Harness()
        await f.store.start(); await f.catalog.send([], status: .missingRoot)
        await eventually { f.store.catalogStatus == .missingRoot }
        XCTAssertTrue(f.store.sessionStatus.contains("root"))
        await f.catalog.send([])
        await eventually { f.store.catalogStatus == .available }
        XCTAssertTrue(f.store.sessionStatus.contains("No local chats"))
        await f.store.stop()
    }
    func testRequestPagingNeverRendersMoreThan100Rows() throws {
        var state = try session("native-two-requests")
        let r = state.requests[0]
        state = DerivedSession(requests: (0..<205).map { i in
            ObservedRequest(key: .init(threadID: Fixture.threadID, responseID: "r\(i)"), usage: r.usage, taskID: r.taskID,
                rootTaskID: nil, runtimeSessionID: nil, timestamp: nil, source: r.source, configuredModel: nil, tools: [])
        }, tasks: [], totals: state.totals, cacheHitPercent: nil, reconciliation: state.reconciliation,
           context: state.context, unattributedTools: [], quarantinedKeys: [], diagnostics: [])
        XCTAssertEqual(RequestPage(session: state, page: 0).rows.count, 100)
        XCTAssertEqual(RequestPage(session: state, page: 1).rows.first?.key.responseID, "r104")
        XCTAssertEqual(RequestPage(session: state, page: 2).rows.count, 5)
    }
    func testOfflineChangedWhileRuntimeIsBeingCreatedPreventsQuotaStart() async throws {
        let gate = RuntimeGate()
        let c = CatalogFake(), r = ReaderFake(), q = ProviderFake()
        let store = SidecarStore(settings: LocalSettings(), factory: { _ in
            await gate.wait()
            return SidecarRuntime(root: URL(fileURLWithPath: "/synthetic"), catalog: c, reader: r, quotas: q, compatibility: "Synthetic")
        })
        let start = Task { await store.start() }
        await eventually { gate.ready }
        await store.setOffline(true)
        gate.release()
        await start.value
        await eventually { store.quota == .unavailable(.offline) }
        let enabled = await q.offline
        XCTAssertTrue(enabled)
        await store.stop()
    }
    func testSettingsReplacementClearsStateAndStopsOldResources() async throws {
        let f = try Harness()
        await f.store.start(); await f.catalog.send([f.a])
        await eventually { !f.store.sessions.isEmpty }
        await f.store.selectSession(id: f.a.id); await f.reader.send(f.stateA)
        await f.quota.send(.available(f.quotaSnapshot))
        await eventually { f.store.session != nil && f.store.quota.lastGood != nil }
        await f.store.applySettings(root: "/new-synthetic-root", executable: "/synthetic-codex")
        XCTAssertNil(f.store.session); XCTAssertNil(f.store.selectedID)
        XCTAssertNil(f.store.quota.lastGood)
        let stops = await f.reader.stops
        XCTAssertEqual(stops, 1)
        await f.reader.send(f.stateA); await f.quota.send(.available(f.quotaSnapshot))
        for _ in 0..<100 { await Task.yield() }
        XCTAssertNil(f.store.session); XCTAssertNil(f.store.quota.lastGood)
        await f.store.stop()
    }
    func testPersistedSettingsContainOnlyAllowedLocalFields() throws {
        let suite = "sidecar.synthetic." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let p = SettingsPersistence(defaults: defaults)
        p.save(LocalSettings(rootOverride: "/synthetic", executableOverride: "/fake", selectedID: "synthetic-a", bucketID: "codex", offline: true))
        XCTAssertTrue(p.load().offline)
        let data = try XCTUnwrap(defaults.data(forKey: "sidecar.localSettings"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["rootOverride", "executableOverride", "selectedID", "bucketID", "offline"]))
    }
    func testRealReaderAppendContinuesOfflineAndStopsOnShutdown() async throws {
        let fixture = try ReaderFixture()
        let source = try fixture.write(ReaderFixture.native(1))
        let catalog = SessionCatalog(watcherHints: false), reader = SessionReader(root: fixture.root, watcherHints: false)
        let clock = QuotaTestClock()
        let transport = QuotaTransportFake(quota: try Fixture.data("weekly-only", ext: "json"))
        let quota = QuotaProvider(scheduler: clock, transportFactory: { transport })
        let root = fixture.root
        let store = SidecarStore(settings: LocalSettings(), factory: { _ in
            SidecarRuntime(root: root, catalog: catalog, reader: reader, quotas: quota, compatibility: "Synthetic")
        })
        await store.start()
        await eventually { !store.sessions.isEmpty }
        await store.selectSession(id: Fixture.threadID)
        await eventually { store.session?.totals.total == 1 }
        await store.setOffline(true)
        try ReaderFixture.append(ReaderFixture.request(2), to: source)
        await reader.refresh()
        await eventually { store.session?.totals.total == 2 }
        XCTAssertEqual(store.quota, .unavailable(.offline))
        await store.stop()
        let running = await reader.workersRunning
        XCTAssertFalse(running)
        let before = try Data(contentsOf: source)
        XCTAssertEqual(before, ReaderFixture.native(2))
        let stopped = await transport.stopped
        XCTAssertGreaterThanOrEqual(stopped, 1)
    }
    private func session(_ name: String) throws -> DerivedSession {
        SessionReducer.reduce(try Fixture.events(name), owningThreadID: Fixture.threadID)
    }
    private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<10000 { if condition() { return }; await Task.yield() }
        XCTFail("Presentation update did not arrive")
    }
}

private actor CatalogFake: SidecarCatalog {
    let stream: AsyncStream<[SessionDescriptor]>
    let continuation: AsyncStream<[SessionDescriptor]>.Continuation
    var lastStatus: SessionCatalog.Status = .available
    var stops = 0
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func sessions(root: URL) -> AsyncStream<[SessionDescriptor]> { stream }
    func send(_ sessions: [SessionDescriptor], status: SessionCatalog.Status = .available) { lastStatus = status; continuation.yield(sessions) }
    func stop() { stops += 1; continuation.finish() }
}
private actor ReaderFake: SidecarReader {
    let stream: AsyncStream<DerivedSession>
    let continuation: AsyncStream<DerivedSession>.Continuation
    var subscriptions = 0; var stops = 0
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func snapshots() -> AsyncStream<DerivedSession> { subscriptions += 1; return stream }
    func select(_ session: SessionDescriptor) {}
    func refresh() {}
    func send(_ s: DerivedSession) { continuation.yield(s) }
    func stop() { stops += 1; continuation.finish() }
}
private actor ProviderFake: SidecarQuotas {
    let stream: AsyncStream<QuotaState>
    let continuation: AsyncStream<QuotaState>.Continuation
    var starts = 0; var stops = 0; var offline = false
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func snapshots() -> AsyncStream<QuotaState> { stream }
    func start() { starts += 1 }
    func refresh(now: Date) {}
    func wake() {}
    func setOffline(_ value: Bool) { offline = value; if value { send(.unavailable(.offline)) } }
    func send(_ s: QuotaState) { continuation.yield(s) }
    func stop() { stops += 1; continuation.finish() }
}
@MainActor
private struct Harness {
    let catalog = CatalogFake(); let reader = ReaderFake(); let quota = ProviderFake()
    let a = SessionDescriptor(id: Fixture.threadID, sourceURLs: [], projectName: "A", cliVersion: "0.160.1", lastActivity: nil, parentThreadID: nil)
    let b = SessionDescriptor(id: "22222222-2222-4222-8222-222222222222", sourceURLs: [], projectName: "B", cliVersion: "0.160.1", lastActivity: nil, parentThreadID: nil)
    let stateA: DerivedSession; let stateB: DerivedSession; let quotaSnapshot: QuotaSnapshot
    let store: SidecarStore
    init() throws {
        stateA = SessionReducer.reduce(try Fixture.events("native-two-requests"), owningThreadID: a.id)
        let bID = b.id
        let text = try Fixture.lines("equal-values-distinct-ids").map { String(decoding: $0, as: UTF8.self).replacingOccurrences(of: Fixture.threadID, with: bID) }
        let events = text.enumerated().compactMap { RolloutDecoder().decodeLine(Data($0.element.utf8), at: .init(fileID: "B", byteOffset: Int64($0.offset))).event }
        stateB = SessionReducer.reduce(events, owningThreadID: b.id)
        quotaSnapshot = try QuotaDecoder.decodeRead(Fixture.data("weekly-only", ext: "json"), receivedAt: Date())
        let c = catalog, r = reader, q = quota
        store = SidecarStore(settings: LocalSettings(), persistence: nil, factory: { _ in
            SidecarRuntime(root: URL(fileURLWithPath: "/synthetic"), catalog: c, reader: r, quotas: q, compatibility: "Synthetic transport")
        })
    }
}

@MainActor
private final class RuntimeGate: @unchecked Sendable {
    var ready = false
    var pending: CheckedContinuation<Void, Never>?
    func wait() async { ready = true; await withCheckedContinuation { pending = $0 } }
    func release() { pending?.resume(); pending = nil }
}
