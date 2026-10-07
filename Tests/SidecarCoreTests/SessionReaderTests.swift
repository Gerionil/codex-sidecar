import XCTest
@testable import SidecarCore

final class SessionReaderTests: XCTestCase, @unchecked Sendable {
    func selected(_ f: ReaderFixture, reader: SessionReader) async throws -> URL {
        let url = try f.write(ReaderFixture.native(1))
        let sessions = await SessionCatalog().discover(root: f.root)
        await reader.select(try XCTUnwrap(sessions.first))
        return url
    }
    func testAppendPartialCompletionAndRestart() async throws {
        let f = try ReaderFixture(); let reader = SessionReader()
        let url = try await selected(f, reader: reader)
        let awaited1 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited1?.totals.total, 1)
        let next = ReaderFixture.request(2)
        try ReaderFixture.append(Data(next.dropLast()), to: url)
        await reader.refresh()
        let awaited2 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited2?.requests.count, 1)
        let awaited3 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited3?.reconciliation.status, .degraded)
        try ReaderFixture.append(Data([10]), to: url); await reader.refresh()
        let awaited4 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited4?.totals.total, 2)
        let awaited5 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited5?.reconciliation.status, .reconciled)
        let restarted = SessionReader()
        await restarted.select((await SessionCatalog().discover(root: f.root))[0])
        let awaited6 = (await reader.currentSnapshot())
        let awaited7 = (await restarted.currentSnapshot())
        XCTAssertEqual(awaited6, awaited7)
        await reader.stop(); await restarted.stop()
    }
    func testTruncationEqualSizeReplacementAndDeletion() async throws {
        let f = try ReaderFixture(); let reader = SessionReader()
        let url = try await selected(f, reader: reader)
        try ReaderFixture.native(2).write(to: url); await reader.refresh()
        let awaited8 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited8?.totals.total, 2)
        try ReaderFixture.native(1).write(to: url); await reader.refresh()
        let awaited9 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited9?.totals.total, 1)
        let changed = String(decoding: ReaderFixture.native(1), as: UTF8.self).replacingOccurrences(of: "response-1", with: "response-9")
        try Data(changed.utf8).write(to: url, options: .atomic); await reader.refresh()
        let awaited10 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited10?.requests.first?.key.responseID, "response-9")
        try FileManager.default.removeItem(at: url); await reader.refresh()
        let awaited11 = (await reader.currentSnapshot())
        XCTAssertNil(awaited11?.totals.total)
        let awaited12 = (await reader.currentSnapshot())
        XCTAssertTrue(awaited12?.diagnostics.contains { $0.category == .sourceUnavailable } == true)
        await reader.stop()
    }
    func testArchiveMoveDuplicatesAndConflicts() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(root: f.root)
        let url = try await selected(f, reader: reader)
        try f.write(ReaderFixture.native(1), "archived_sessions/copy.jsonl")
        try FileManager.default.removeItem(at: url)
        await reader.reconcileCatalog()
        let awaited13 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited13?.totals.total, 1)
        let conflict = String(decoding: ReaderFixture.native(1), as: UTF8.self).replacingOccurrences(of: "\"total_tokens\":1}", with: "\"total_tokens\":2}")
        try f.write(Data(conflict.utf8), "sessions/conflict.jsonl")
        await reader.reconcileCatalog()
        let awaited14 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited14?.quarantinedKeys.count, 1)
        let awaited15 = (await reader.currentSnapshot())
        XCTAssertNil(awaited15?.totals.total)
        await reader.stop()
    }
    func testMalformedOversizedAndDecoderDiagnosticsDegradeCoverage() async throws {
        let f = try ReaderFixture(); let reader = SessionReader()
        let url = try await selected(f, reader: reader)
        try ReaderFixture.append(Data("PRIVATE_MARKER bad\n".utf8), to: url)
        try ReaderFixture.append(Data(repeating: 65, count: 8 * 1024 * 1024 + 1) + Data([10]), to: url)
        try ReaderFixture.append(ReaderFixture.request(2), to: url)
        await reader.refresh()
        let awaited16 = (await reader.currentSnapshot())
        let state = try XCTUnwrap(awaited16)
        XCTAssertEqual(state.totals.total, 2)
        XCTAssertEqual(state.reconciliation.status, .degraded)
        XCTAssertEqual(state.sourceAvailability, .partial)
        XCTAssertTrue(state.diagnostics.contains { $0.category == .oversizedRecord })
        XCTAssertTrue(state.diagnostics.contains { $0.category == .malformedRecord })
        XCTAssertFalse(String(describing: state).contains("PRIVATE_MARKER"))
        await reader.stop()
    }
    func testSelectionGenerationRejectsPendingRead() async throws {
        let f = try ReaderFixture()
        try f.write(ReaderFixture.native(10000), "sessions/old.jsonl")
        try f.write(ReaderFixture.native(1, id: "new"), "sessions/new.jsonl")
        let sessions = await SessionCatalog().discover(root: f.root)
        let reader = SessionReader()
        let old = Task { await reader.select(sessions.first { $0.id == Fixture.threadID }!) }
        while !(await reader.isReading) { await Task.yield() }
        await reader.select(sessions.first { $0.id == "new" }!)
        await old.value
        let awaited17 = (await reader.currentSnapshot())
        XCTAssertEqual(awaited17?.requests.first?.key.threadID, "new")
        await reader.stop()
    }
    func testStoppedStreamFinishesAndReaderReleasesState() async throws {
        let f = try ReaderFixture(); let reader = SessionReader()
        _ = try await selected(f, reader: reader)
        let stream = await reader.snapshots()
        await reader.stop()
        var count = 0
        for await _ in stream { count += 1 }
        XCTAssertLessThanOrEqual(count, 1)
        let awaited18 = (await reader.currentSnapshot())
        XCTAssertNil(awaited18)
    }
    func testNewEarlierSourceHasIndependentProvenance() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(root: f.root, watcherHints: false)
        try f.write(ReaderFixture.native(1), "sessions/z.jsonl")
        await reader.select((await SessionCatalog().discover(root: f.root))[0])
        let second = ReaderFixture.header() + ReaderFixture.request(2)
        try f.write(second, "sessions/a.jsonl")
        await reader.reconcileCatalog()
        let state = await reader.currentSnapshot()
        XCTAssertEqual(state?.totals.total, 2)
        XCTAssertEqual(Set(state!.requests.map { $0.source.fileID }).count, 2)
        await reader.stop()
    }

    func testTenThousandRequestReplayAndMeasuredStatFallback() async throws {
        let f = try ReaderFixture()
        let bytes = ReaderFixture.native(10000)
        let url = try f.write(bytes)
        let descriptor = (await SessionCatalog().discover(root: f.root))[0]
        let reader = SessionReader(watcherHints: false)
        let start = Date()
        await reader.select(descriptor)
        let replaySeconds = Date().timeIntervalSince(start)
        let initial = await reader.currentSnapshot()
        XCTAssertEqual(initial?.requests.count, 10000)
        XCTAssertEqual(initial?.totals.total, 10000)
        XCTAssertNil(initial?.totals.input)
        XCTAssertNil(initial?.cacheHitPercent)
        let appended = expectation(description: "Stat fallback publishes appended request")
        let stream = await reader.snapshots()
        let appendStart = Date()
        let observer = Task {
            for await state in stream where state.requests.count == 10001 {
                appended.fulfill(); return Date().timeIntervalSince(appendStart)
            }
            return Double.infinity
        }
        try ReaderFixture.append(ReaderFixture.request(10001), to: url)
        await fulfillment(of: [appended], timeout: 2)
        observer.cancel()
        let appendSeconds = await observer.value
        XCTAssertLessThanOrEqual(appendSeconds, 2)
        let stopStart = Date(); await reader.stop()
        let cancellationSeconds = Date().timeIntervalSince(stopStart)
        print("STAGE3_MEASURE replay_seconds=\(replaySeconds) append_stat_seconds=\(appendSeconds) stop_seconds=\(cancellationSeconds) bytes=\(bytes.count) requests=10000")
    }
    func testCancellationWhileReadingAndStreamTermination() async throws {
        let f = try ReaderFixture()
        try f.write(ReaderFixture.native(10000))
        let descriptor = (await SessionCatalog().discover(root: f.root))[0]
        let reader = SessionReader(watcherHints: false)
        let pending = Task { await reader.select(descriptor) }
        while !(await reader.isReading) { await Task.yield() }
        try await Task.sleep(for: .milliseconds(20))
        let start = Date(); await reader.stop(); await pending.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        let state = await reader.currentSnapshot()
        XCTAssertNil(state)
        print("STAGE3_MEASURE pending_cancel_seconds=\(Date().timeIntervalSince(start))")
        let url = try await selected(f, reader: reader)
        let waiting = expectation(description: "Stream has initial state")
        let stream = await reader.snapshots()
        let observer = Task {
            var initial = true
            for await _ in stream {
                if initial { waiting.fulfill(); initial = false }
            }
        }
        await fulfillment(of: [waiting], timeout: 1)
        observer.cancel(); await observer.value
        // Give onTermination's actor hop a chance to release the workers.
        while await reader.workersRunning { await Task.yield() }
        try ReaderFixture.append(ReaderFixture.request(2), to: url)
        try await Task.sleep(for: .milliseconds(1100))
        let unchanged = await reader.currentSnapshot()
        XCTAssertEqual(unchanged?.requests.count, 1)
        await reader.stop()
    }
    func testMissingOptionalCountersForeignOwnershipAndInvalidCounters() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(watcherHints: false)
        let data = ReaderFixture.native(1) + ReaderFixture.request(2, id: "foreign")
            + Data("{\"type\":\"token_usage_record\",\"payload\":{\"thread_id\":\"\(Fixture.threadID)\",\"turn_id\":\"task\",\"response_id\":\"invalid\",\"usage\":{\"total_tokens\":-1}}}\n".utf8)
        try f.write(data)
        await reader.select((await SessionCatalog().discover(root: f.root))[0])
        let state = await reader.currentSnapshot()
        XCTAssertEqual(state?.requests.count, 1)
        XCTAssertEqual(state?.totals.total, 1)
        XCTAssertNil(state?.totals.input)
        XCTAssertNil(state?.cacheHitPercent)
        XCTAssertEqual(state?.reconciliation.status, .degraded)
        XCTAssertTrue(state?.diagnostics.contains { $0.category == .invalidCounters } == true)
        await reader.stop()
    }
    func testInPlaceEqualSizeReplacementAndGrowingRewrite() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(watcherHints: false)
        let url = try await selected(f, reader: reader)
        let changed = Data(String(decoding: ReaderFixture.native(1), as: UTF8.self)
            .replacingOccurrences(of: "response-1", with: "response-9").utf8)
        try changed.write(to: url); await reader.refresh()
        var state = await reader.currentSnapshot()
        XCTAssertEqual(state?.requests.first?.key.responseID, "response-9")
        try ReaderFixture.native(2).write(to: url); await reader.refresh()
        state = await reader.currentSnapshot()
        XCTAssertEqual(state?.totals.total, 2)
        XCTAssertFalse(state?.requests.contains { $0.key.responseID == "response-9" } == true)
        await reader.stop()
    }

    @MainActor
    func testBackgroundReplayKeepsMainActorResponsive() async throws {
        let f = try ReaderFixture(); try f.write(ReaderFixture.native(10000))
        let descriptor = (await SessionCatalog().discover(root: f.root))[0]
        let reader = SessionReader(watcherHints: false)
        var heartbeats = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                heartbeats += 1
                do { try await Task.sleep(for: .milliseconds(5)) } catch { break }
            }
        }
        await reader.select(descriptor)
        heartbeat.cancel(); await heartbeat.value
        XCTAssertGreaterThan(heartbeats, 2)
        let state = await reader.currentSnapshot()
        XCTAssertEqual(state?.requests.count, 10000)
        await reader.stop()
    }
    func testSelectedSourceSymlinkReplacementIsUnavailable() async throws {
        let f = try ReaderFixture(); let outside = try ReaderFixture()
        let reader = SessionReader(watcherHints: false)
        let url = try await selected(f, reader: reader)
        let target = try outside.write(ReaderFixture.native(2))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        await reader.refresh()
        let state = await reader.currentSnapshot()
        XCTAssertEqual(state?.sourceAvailability, .unavailable)
        XCTAssertNil(state?.totals.total)
        await reader.stop()
    }

    func testInteriorRewriteWithGrowthRebuildsAndQuarantinesConflict() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(watcherHints: false)
        let original = ReaderFixture.native(1000)
        let url = try f.write(original)
        await reader.select((await SessionCatalog().discover(root: f.root))[0])
        var replacement = Data(String(decoding: original, as: UTF8.self)
            .replacingOccurrences(of: "response-500\"", with: "response-999\"").utf8)
        replacement.append(ReaderFixture.request(1001))
        try replacement.write(to: url); await reader.refresh()
        let state = await reader.currentSnapshot()
        XCTAssertFalse(state?.requests.contains { $0.key.responseID == "response-500" } == true)
        XCTAssertTrue(state?.quarantinedKeys.contains { $0.responseID == "response-999" } == true)
        XCTAssertEqual(state?.requests.count, 999)
        await reader.stop()
    }
    func testReplacementMustStartWithOwningHeader() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(watcherHints: false)
        let url = try await selected(f, reader: reader)
        try (Data("{\"type\":\"unknown\"}\n".utf8) + ReaderFixture.native(1)).write(to: url)
        await reader.refresh()
        let state = await reader.currentSnapshot()
        XCTAssertTrue(state?.requests.isEmpty == true)
        XCTAssertNil(state?.totals.total)
        XCTAssertEqual(state?.reconciliation.status, .degraded)
        await reader.stop()
    }
    func testOversizedInitialHeaderCannotAuthorizeLaterHeader() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(watcherHints: false)
        let data = Data(repeating: 65, count: 8 * 1024 * 1024 + 1) + Data([10]) + ReaderFixture.native(1)
        let url = try f.write(data)
        let descriptor = SessionDescriptor(id: Fixture.threadID, sourceURLs: [url], projectName: nil, cliVersion: nil, lastActivity: nil, parentThreadID: nil)
        await reader.select(descriptor)
        let state = await reader.currentSnapshot()
        XCTAssertTrue(state?.requests.isEmpty == true)
        XCTAssertNil(state?.totals.total)
        XCTAssertEqual(state?.reconciliation.status, .degraded)
        await reader.stop()
    }

    func testFilesystemReplayMatchesStageTwoFixture() async throws {
        let f = try ReaderFixture()
        let lines = try Fixture.lines("native-two-requests")
        var bytes = Data(), events: [MetricEvent] = [], offset: Int64 = 0
        for line in lines {
            let decoded = RolloutDecoder().decodeLine(line, at: .init(fileID: "source-0", byteOffset: offset))
            if let event = decoded.event { events.append(event) }
            bytes.append(line); bytes.append(10); offset += Int64(line.count) + 1
        }
        try f.write(bytes)
        let reader = SessionReader(watcherHints: false)
        await reader.select((await SessionCatalog().discover(root: f.root))[0])
        let state = await reader.currentSnapshot()
        XCTAssertEqual(state, SessionReducer.reduce(events, owningThreadID: Fixture.threadID))
        XCTAssertEqual(state?.totals.total, 180)
        XCTAssertEqual(state?.cacheHitPercent ?? -1, 66.6666666667, accuracy: 0.00001)
        XCTAssertEqual(state?.context.window, 1000)
        XCTAssertNil(state?.context.exactCurrentUsage)
        await reader.stop()
    }
    func testSelectedUnreadableSourceRecoversWithoutOldTotals() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(watcherHints: false)
        let url = try await selected(f, reader: reader)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        await reader.refresh()
        var state = await reader.currentSnapshot()
        XCTAssertEqual(state?.sourceAvailability, .unavailable)
        XCTAssertNil(state?.totals.total)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        await reader.refresh()
        state = await reader.currentSnapshot()
        XCTAssertEqual(state?.totals.total, 1)
        XCTAssertEqual(state?.sourceAvailability, .available)
        await reader.stop()
    }

    func testCancelledCatalogReconciliationDoesNotWedgeLaterRefresh() async throws {
        let f = try ReaderFixture(); let reader = SessionReader(root: f.root, watcherHints: false)
        _ = try await selected(f, reader: reader)
        let padding = String(repeating: "a", count: 7 * 1024 * 1024)
        let slow = try f.write(Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"other\",\"ignored\":\"\(padding)\"}}\n".utf8), "sessions/slow.jsonl")
        let pending = Task { await reader.reconcileCatalog() }
        try await Task.sleep(for: .milliseconds(10))
        pending.cancel(); await pending.value
        try FileManager.default.removeItem(at: slow)
        let complete = expectation(description: "Later reconciliation completes after caller cancellation")
        let next = Task { await reader.reconcileCatalog(); complete.fulfill() }
        await fulfillment(of: [complete], timeout: 1)
        await reader.stop(); await next.value
    }

}
