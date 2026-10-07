import XCTest
@testable import SidecarCore

final class SessionReducerTests: XCTestCase {
    func testNativeRequestsStayDistinctFromTaskAndSnapshots() throws {
        let events = try Fixture.events("native-two-requests")
        let state = SessionReducer.reduce(events, owningThreadID: Fixture.threadID)
        XCTAssertEqual(state.requests.count, 2)
        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertEqual(state.totals.input, 150)
        XCTAssertEqual(state.totals.cachedInput, 100)
        XCTAssertEqual(state.totals.output, 30)
        XCTAssertEqual(state.totals.reasoning, 7)
        XCTAssertEqual(try XCTUnwrap(state.cacheHitPercent), 66.6666667, accuracy: 0.0001)
        XCTAssertEqual(SessionReducer.reduce(events + events, owningThreadID: Fixture.threadID), state)
    }

    func testEqualValuesWithDistinctIDsCountTwice() throws {
        let state = try reduce("equal-values-distinct-ids")
        XCTAssertEqual(state.requests.count, 2)
        XCTAssertEqual(state.totals.total, 240)
    }

    func testConflictingIDIsRetractedAndQuarantined() throws {
        let state = try reduce("conflicting-response-id")
        XCTAssertTrue(state.requests.isEmpty)
        XCTAssertNil(state.totals.total)
        XCTAssertEqual(state.quarantinedKeys.count, 1)
        XCTAssertEqual(state.reconciliation.status, .degraded)
        XCTAssertTrue(state.diagnostics.contains { $0.category == .conflictingResponse })
    }

    func testForeignHistoryDoesNotSwitchOwnership() throws {
        let state = try reduce("foreign-history")
        XCTAssertEqual(state.requests.count, 1)
        XCTAssertEqual(state.totals.total, 120)
        XCTAssertEqual(state.reconciliation.baseline?.total, 500)
    }

    func testExplicitZeroRemainsARequestWithUnavailableCacheRate() throws {
        let state = try reduce("native-zero-usage")
        XCTAssertEqual(state.requests.count, 1)
        XCTAssertEqual(state.totals.total, 0)
        XCTAssertNil(state.cacheHitPercent)
    }

    func testPartialBreakdownDoesNotLookComplete() throws {
        let state = try reduce("partial-native-usage")
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertNil(state.totals.input)
        XCTAssertNil(state.totals.cachedInput)
        XCTAssertNil(state.cacheHitPercent)
    }

    func testMissingTaskStartPreservesUsageAndDiagnosesGroup() throws {
        let state = try reduce("missing-task-start")
        XCTAssertEqual(state.totals.total, 120)
        XCTAssertEqual(state.tasks.first?.hasStart, false)
        XCTAssertTrue(state.diagnostics.contains { $0.category == .missingTaskStart })
    }

    func testInterruptedActivityNeverManufacturesRequest() throws {
        let state = try reduce("interrupted-no-usage")
        XCTAssertTrue(state.requests.isEmpty)
        XCTAssertEqual(state.tasks.first?.status, .interrupted)
        XCTAssertEqual(state.tasks.first?.usageReported, false)
    }

    func testAggregateOverflowIsUnavailableRatherThanWrapping() throws {
        let state = try reduce("aggregate-overflow")
        XCTAssertEqual(state.requests.count, 2)
        XCTAssertNil(state.totals.total)
        XCTAssertTrue(state.diagnostics.contains { $0.category == .aggregateOverflow })
    }

    func testUnidentifiedSourceCannotAuthorizeOwnedRecords() throws {
        let events = try Fixture.events("missing-task-start").filter {
            if case .header = $0 { return false }; return true
        }
        let state = SessionReducer.reduce(events, owningThreadID: Fixture.threadID)
        XCTAssertTrue(state.requests.isEmpty)
        XCTAssertEqual(state.reconciliation.status, .degraded)
    }

    func testDuplicateSourceCopiesDeduplicateByOwnedResponseIdentity() throws {
        let first = try Fixture.events("native-two-requests")
        // Same invented stream, decoded with a different logical file identity.
        let decoder = RolloutDecoder()
        let second = try Fixture.lines("native-two-requests").enumerated().compactMap {
            decoder.decodeLine($0.element, at: SourcePosition(fileID: "copy", byteOffset: Int64($0.offset))).event
        }
        let state = SessionReducer.reduce(first + second, owningThreadID: Fixture.threadID)
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertEqual(state.requests.count, 2)
    }

    private func reduce(_ name: String) throws -> DerivedSession {
        SessionReducer.reduce(try Fixture.events(name), owningThreadID: Fixture.threadID)
    }
}
