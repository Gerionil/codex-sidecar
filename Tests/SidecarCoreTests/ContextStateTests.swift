import XCTest
@testable import SidecarCore

final class ContextStateTests: XCTestCase {
    func testConfiguredModelWindowAndFootprintHaveSeparateMeaning() throws {
        let state = try reduce("native-two-requests")
        XCTAssertEqual(state.context.configuredModel?.model, "example-model")
        XCTAssertEqual(try XCTUnwrap(state.requests.first).configuredModel?.model, "example-model")
        XCTAssertEqual(state.context.window, 1000)
        XCTAssertEqual(state.context.lastRequestFootprint?.total, 60)
        XCTAssertEqual(state.context.lastRequestRatio, 0.06)
        XCTAssertNil(state.context.exactCurrentUsage)
    }
    func testModelChangeWithoutFreshWindowInvalidatesCapacity() throws {
        let state = try reduce("model-window-change")
        XCTAssertEqual(state.context.configuredModel?.model, "other-model")
        XCTAssertNil(state.context.window)
        XCTAssertTrue(state.context.footprintIsHistorical)
        XCTAssertNil(state.context.lastRequestRatio)
        XCTAssertNil(state.context.exactCurrentUsage)
    }
    func testCompactionMakesContextHistoricalUntilFreshEvidence() throws {
        let events = try Fixture.events("compaction-checkpoint")
        let state = SessionReducer.reduce(Array(events.dropLast()), owningThreadID: Fixture.threadID)
        XCTAssertTrue(state.context.footprintIsHistorical)
        XCTAssertNil(state.context.window)
        XCTAssertNil(state.context.exactCurrentUsage)
    }
    func testInterruptionInvalidatesContextWithoutFabricatedFootprint() throws {
        let state = try reduce("interrupted-no-usage")
        XCTAssertNil(state.context.lastRequestFootprint)
        XCTAssertNil(state.context.window)
        XCTAssertNil(state.context.exactCurrentUsage)
    }
    func testWindowChangeMakesOldFootprintHistorical() throws {
        let state = try reduce("window-change")
        XCTAssertEqual(state.context.window, 2000)
        XCTAssertTrue(state.context.footprintIsHistorical)
        XCTAssertNil(state.context.lastRequestRatio)
    }
    func testFreshNativeAndMatchingWindowSnapshotRecoverAfterCompaction() throws {
        let state = try reduce("compaction-fresh-window")
        XCTAssertFalse(state.context.footprintIsHistorical)
        XCTAssertEqual(state.context.window, 1000)
        XCTAssertEqual(state.context.lastRequestRatio, 0.06)
    }
    func testConcurrentSnapshotCannotAssignCapacityToLatestRequest() throws {
        let state = try reduce("concurrent-context-snapshot")
        XCTAssertNil(state.context.window)
        XCTAssertNil(state.context.lastRequestRatio)
    }
    private func reduce(_ name: String) throws -> DerivedSession {
        SessionReducer.reduce(try Fixture.events(name), owningThreadID: Fixture.threadID)
    }
}
