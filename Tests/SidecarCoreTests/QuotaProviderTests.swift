import XCTest
@testable import SidecarCore

final class QuotaProviderTests: XCTestCase, @unchecked Sendable {
    func setup(_ fixture: String = "weekly-only", offline: Bool = false) throws -> (QuotaProvider, QuotaTransportFake, QuotaTestClock, QuotaFactoryFake) {
        let clock = QuotaTestClock(), fake = QuotaTransportFake(quota: try Fixture.data(fixture, ext: "json"))
        let factory = QuotaFactoryFake([fake])
        return (QuotaProvider(offline: offline, scheduler: clock, transportFactory: { try await factory.make() }), fake, clock, factory)
    }
    func testStartPollingManualWakeAndStaleness() async throws {
        let (p, f, c, _) = try setup()
        let checked1 = await p.currentState()
        XCTAssertEqual(checked1, .loading)
        await p.start(); let first = await p.currentState().lastGood
        XCTAssertEqual(first?.buckets.first?.windows.first?.label, "Weekly")
        await quotaEventually { c.sleepers > 0 }; c.advance(59)
        let checked2 = await f.reads
        XCTAssertEqual(checked2, 1)
        c.advance(1); await quotaEventually { let reads = await f.reads; let busy = await p.isRefreshing; return reads == 2 && !busy }
        await p.refresh(now: c.now());
        let checked3 = await f.reads
        XCTAssertEqual(checked3, 3)
        await f.configure(hold: true)
        let waking = Task { await p.wake() }
        await quotaEventually { await f.waiting != nil }
        let wakeState = await p.currentState()
        guard case .stale(_, .wake) = wakeState else { return XCTFail("Wake must stale last good") }
        await f.complete(); await waking.value
        await f.configure(failure: .requestFailed)
        await p.refresh(now: c.now())
        guard case .error(.requestFailed, .some) = await p.currentState() else { return XCTFail("Retain last good") }
        await p.stop()
    }
    func testSingleFlightAndSparseHintsDoNotMutateCacheOrFreshness() async throws {
        let (p, f, c, _) = try setup("multiple-buckets")
        await p.start(); let before = await p.currentState().lastGood
        for _ in 0..<10 { await f.hint("account/rateLimits/updated") }
        await quotaEventually { c.sleepers > 0 }
        let checked4 = await p.currentState().lastGood
        XCTAssertEqual(checked4, before)
        let checked5 = await f.reads
        XCTAssertEqual(checked5, 1)
        await f.configure(hold: true)
        let manual = Task { await p.refresh(now: c.now()) }
        await quotaEventually { await f.waiting != nil }
        let overlap = Task { await p.refresh(now: c.now()) }
        await Task.yield()
        let checked6 = await f.reads
        XCTAssertEqual(checked6, 2)
        await f.complete(); await manual.value; await overlap.value
        let max = await f.maximumActive;
        XCTAssertEqual(max, 1)
        await f.configure(quota: try Fixture.data("empty-map", ext: "json"))
        await p.refresh(now: c.now());
        let checked7 = (await p.currentState().lastGood)?.buckets.isEmpty == true
        XCTAssertTrue(checked7)
        await p.stop()
    }
    func testRetriesAre60Then120Then300AndManualBypasses() async throws {
        let (p, f, c, _) = try setup()
        await f.configure(failure: .requestFailed); await p.start()
        for delay in [60.0, 120, 300, 300] {
            let reads = await f.reads
            await quotaEventually { c.sleepers > 0 }
            c.advance(delay - 1); await Task.yield()
        let checked8 = await f.reads
        XCTAssertEqual(checked8, reads)
            c.advance(1); await quotaEventually { await f.reads == reads + 1 }
        }
        let before = await f.reads; await p.refresh(now: c.now());
        let checked9 = await f.reads
        XCTAssertEqual(checked9, before + 1)
        await p.stop()
    }
    func test120SecondExpiryWhileReadPending() async throws {
        let (p, f, c, _) = try setup(); await p.start(); await f.configure(hold: true)
        await quotaEventually { c.sleepers > 0 }; c.advance(60)
        await quotaEventually { await f.waiting != nil }
        await quotaEventually { c.sleepers > 0 }; c.advance(60)
        await quotaEventually { if case .stale(_, .age) = await p.currentState() { return true }; return false }
        await f.complete(); await p.stop()
    }
    func testPastResetTriggersOneRefreshWithoutAssumingRecovery() async throws {
        let (p, f, c, _) = try setup()
        let reset = Int64(c.now().timeIntervalSince1970) + 10
        await f.configure(quota: quotaBytes("{\"rateLimits\":{\"primary\":{\"usedPercent\":75,\"resetsAt\":\(reset)}}}"))
        await p.start(); await f.configure(hold: true)
        await quotaEventually { c.sleepers > 0 }; c.advance(10)
        await quotaEventually { await f.waiting != nil }
        guard case .stale(let last, .resetPassed) = await p.currentState() else { return XCTFail("Expected stale reset") }
        XCTAssertEqual(last.buckets[0].windows[0].usedPercent, 75)
        await f.complete(); await quotaEventually { await f.active == 0 }
        c.advance(1); await Task.yield();
        let checked10 = await f.reads
        XCTAssertEqual(checked10, 2)
        await p.stop()
    }
    func testObsoleteAccountRepliesAndNotificationsCannotPublish() async throws {
        let clock = QuotaTestClock()
        let old = QuotaTransportFake(quota: try Fixture.data("weekly-only", ext: "json"))
        let new = QuotaTransportFake(quota: try Fixture.data("empty-map", ext: "json"))
        let factory = QuotaFactoryFake([old, new])
        let p = QuotaProvider(scheduler: clock, transportFactory: { try await factory.make() })
        await old.configure(hold: true)
        let pending = Task { await p.start() }; await quotaEventually { await old.waiting != nil }
        await p.accountChanged()
        let checked11 = (await p.currentState().lastGood)?.buckets.isEmpty == true
        XCTAssertTrue(checked11)
        let generation = await p.currentState().lastGood?.accountGeneration
        await old.hint("account/updated"); await old.complete(); await pending.value
        let checked12 = await p.currentState().lastGood?.accountGeneration
        XCTAssertEqual(checked12, generation)
        let checked13 = (await p.currentState().lastGood)?.buckets.isEmpty == true
        XCTAssertTrue(checked13)
        await p.stop()
    }
    func testPollingDetectsAccountChangeAndAuthLossClearsValues() async throws {
        let (p, f, c, _) = try setup(); await p.start()
        let generation = await p.currentState().lastGood?.accountGeneration
        await f.configure(account: quotaBytes(#"{"account":{"type":"chatgpt","email":"synthetic-b@example.invalid"}}"#))
        await p.refresh(now: c.now())
        let checked14 = await p.currentState().lastGood?.accountGeneration
        XCTAssertNotEqual(checked14, generation)
        for (raw, expected) in [(#"{"account":null}"#, QuotaFailure.authenticationAbsent), (#"{"account":{"type":"apiKey"}}"#, .apiKeyOnly)] {
            await f.configure(account: quotaBytes(raw)); await p.refresh(now: c.now())
        let checked15 = await p.currentState()
        XCTAssertEqual(checked15, .unavailable(expected))
        }
        await p.stop()
    }
    func testOfflineDoesNotConstructTransportAndLocalParserStillWorks() async throws {
        let (p, f, c, factory) = try setup(offline: true)
        await p.start(); await p.refresh(now: c.now()); await p.wake()
        let count = await factory.count;
        let checked16 = await f.reads
        XCTAssertEqual(count, 0); XCTAssertEqual(checked16, 0)
        let checked17 = await p.currentState()
        XCTAssertEqual(checked17, .unavailable(.offline))
        XCTAssertEqual(try Fixture.events("native-two-requests").filter { if case .usageRecord = $0 { return true }; return false }.count, 2)
        await p.setOffline(false);
        let checked18 = await f.reads
        XCTAssertEqual(checked18, 1)
        await p.setOffline(true);
        let checked19 = await p.currentState().lastGood
        XCTAssertNil(checked19)
        let stops = await f.stopped;
        XCTAssertEqual(stops, 1); await p.stop()
    }
    func testUnavailableReasonsAndMalformedRead() async throws {
        for reason in [QuotaFailure.missingExecutable, .unsupportedProtocol, .processExited, .timeout] {
            let clock = QuotaTestClock()
            let p = QuotaProvider(scheduler: clock, transportFactory: { throw reason })
            await p.start();
        let checked20 = await p.currentState()
        XCTAssertEqual(checked20, .unavailable(reason)); await p.stop()
        }
        let (p, f, c, _) = try setup(); await p.start()
        await f.configure(quota: quotaBytes("PRIVATE_MARKER")); await p.refresh(now: c.now())
        guard case .error(.malformedReply, .some) = await p.currentState() else { return XCTFail("Expected retained values") }
        let checked21 = String(describing: await p.currentState()).contains("PRIVATE_MARKER")
        XCTAssertFalse(checked21); await p.stop()
    }
    func testBoundedSnapshotBufferAndStopFinishesStreams() async throws {
        let (p, _, c, _) = try setup()
        let stream = await p.snapshots(); await p.start()
        for _ in 0..<5 { await p.refresh(now: c.now()) }
        var iterator = stream.makeAsyncIterator(); let last = await iterator.next()
        guard case .available = last else { return XCTFail("Latest value must survive bounded buffer") }
        await p.stop(); let next = await iterator.next();
        XCTAssertNil(next)
        let stoppedStream = await p.snapshots(); var stopped = stoppedStream.makeAsyncIterator()
        let checked22 = await stopped.next()
        XCTAssertNil(checked22)
    }
}

extension QuotaProviderTests {
    func testNotificationAccountChangeClearsGoodStateAndRestartsOwnedTransport() async throws {
        let clock = QuotaTestClock()
        let old = QuotaTransportFake(quota: try Fixture.data("weekly-only", ext: "json"))
        let new = QuotaTransportFake(quota: try Fixture.data("empty-map", ext: "json"))
        await new.configure(hold: true)
        let factory = QuotaFactoryFake([old, new])
        let p = QuotaProvider(scheduler: clock, transportFactory: { try await factory.make() })
        await p.start(); await old.hint("account/updated")
        await quotaEventually { await new.waiting != nil }
        let state = await p.currentState(); XCTAssertNil(state.lastGood)
        await new.complete(); await quotaEventually { await p.currentState().lastGood != nil }
        let stopped = await old.stopped; XCTAssertEqual(stopped, 1)
        await p.stop()
    }
    func testLastSubscriberCancellationStopsOwnedResources() async throws {
        let (p, f, _, _) = try setup()
        let stream = await p.snapshots()
        let consuming = Task { for await _ in stream {} }
        await p.start(); consuming.cancel(); await consuming.value
        await quotaEventually { await f.stopped == 1 }
        let last = await p.currentState().lastGood; XCTAssertNil(last)
        await p.stop()
    }
}
