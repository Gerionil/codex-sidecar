import XCTest
@testable import SidecarCore

final class ReconciliationTests: XCTestCase {
    func testZeroBaselineReconcilesWithoutAddingMirrors() throws {
        let state = try reduce("native-two-requests")
        XCTAssertEqual(state.reconciliation.status, .reconciled)
        XCTAssertEqual(state.reconciliation.baseline?.total, 0)
        XCTAssertEqual(state.reconciliation.reportedCumulative?.total, 180)
    }
    func testPositiveBaselineIsSeparatePartialHistory() throws {
        let state = try reduce("positive-baseline")
        XCTAssertEqual(state.totals.total, 120)
        XCTAssertEqual(state.reconciliation.baseline?.total, 500)
        XCTAssertEqual(state.reconciliation.reportedCumulative?.total, 620)
        XCTAssertEqual(state.reconciliation.status, .partialHistory)
    }
    func testCounterDecreaseDegradesContinuityWithoutLosingRows() throws {
        let state = try reduce("native-counter-reset")
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertEqual(state.reconciliation.status, .degraded)
        XCTAssertEqual(state.reconciliation.reportedCumulative?.total, 60)
    }
    func testLegacySnapshotUsesLatestEvenAfterReset() throws {
        let state = try reduce("legacy-only")
        XCTAssertTrue(state.requests.isEmpty)
        XCTAssertNil(state.totals.total)
        XCTAssertEqual(state.reconciliation.status, .legacySnapshot)
        XCTAssertEqual(state.reconciliation.reportedCumulative?.total, 60)
    }
    func testLegacyToNativeDoesNotAddLegacyHistory() throws {
        let state = try reduce("legacy-to-native")
        XCTAssertEqual(state.totals.total, 120)
        XCTAssertEqual(state.reconciliation.status, .partialHistory)
        XCTAssertEqual(state.reconciliation.baseline?.total, 500)
    }
    func testResumeDuplicateDoesNotBreakReconciliation() throws {
        let state = try reduce("resume-replay")
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertEqual(state.reconciliation.status, .reconciled)
    }
    func testCheckpointsNeverCreateOrResetObservedRequests() throws {
        let state = try reduce("compaction-checkpoint")
        XCTAssertEqual(state.requests.count, 2)
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertEqual(state.reconciliation.status, .reconciled)
        let checkpoint = try reduce("checkpoint-only")
        XCTAssertTrue(checkpoint.requests.isEmpty)
        XCTAssertEqual(checkpoint.reconciliation.reportedCumulative?.total, 620)
        XCTAssertNotEqual(checkpoint.reconciliation.status, .reconciled)
    }
    func testContextFullSnapshotIsNotRequest() throws {
        let state = try reduce("context-full-snapshot")
        XCTAssertTrue(state.requests.isEmpty)
        XCTAssertEqual(state.reconciliation.reportedCumulative?.total, 1000)
    }
    func testLegacyTransitionPreservesPartialHistoryEvenAfterCounterReset() throws {
        let state = try reduce("legacy-native-reset")
        XCTAssertEqual(state.totals.total, 120)
        XCTAssertEqual(state.reconciliation.status, .partialHistory)
    }
    func testCheckpointSeedsReportedBaselineWithoutOwnedResponse() throws {
        let state = try reduce("checkpoint-seeded-native")
        XCTAssertEqual(state.totals.total, 120)
        XCTAssertEqual(state.reconciliation.baseline?.total, 500)
        XCTAssertEqual(state.reconciliation.status, .partialHistory)
    }
    func testCheckpointDisagreementDegradesReconciliation() throws {
        XCTAssertEqual(try reduce("checkpoint-disagreement").reconciliation.status, .degraded)
    }
    func testComponentDisagreementIsNotHiddenByMatchingTotal() throws {
        XCTAssertEqual(try reduce("component-cumulative-disagreement").reconciliation.status, .degraded)
    }
    func testMissingEarlyCumulativeNeverClaimsFullContinuity() throws {
        XCTAssertNotEqual(try reduce("missing-cumulative").reconciliation.status, .reconciled)
    }
    func testCopiedCompactionStreamDoesNotDegradeReconciliation() throws {
        let events = try Fixture.events("compaction-checkpoint")
        let copy = try Fixture.lines("compaction-checkpoint").enumerated().compactMap {
            RolloutDecoder().decodeLine($0.element, at: SourcePosition(fileID: "copy", byteOffset: Int64($0.offset))).event
        }
        let state = SessionReducer.reduce(events + copy, owningThreadID: Fixture.threadID)
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertEqual(state.reconciliation.status, .reconciled)
    }
    func testEmptyCumulativeCannotCertifyFullCoverage() throws {
        let state = try reduce("empty-cumulative")
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertEqual(state.reconciliation.status, .partialHistory)
        XCTAssertNil(state.reconciliation.reportedCumulative?.total)
    }
    func testOverriddenSnapshotDoesNotCertifyNativeContinuity() throws {
        let state = try reduce("native-context-full-snapshot")
        XCTAssertEqual(state.totals.total, 120)
        XCTAssertEqual(state.requests.count, 1)
        XCTAssertEqual(state.reconciliation.reportedCumulative?.total, 120)
        XCTAssertEqual(state.reconciliation.status, .degraded)
    }
    private func reduce(_ name: String) throws -> DerivedSession {
        SessionReducer.reduce(try Fixture.events(name), owningThreadID: Fixture.threadID)
    }
}
