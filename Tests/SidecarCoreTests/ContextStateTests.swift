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
    func testOlderPrefixCopyDoesNotReplaceLatestTaskContext() throws {
        let full = try Fixture.events("multiple-task-context")
        let prefix = try Fixture.lines("multiple-task-context").prefix(5).enumerated().compactMap {
            RolloutDecoder().decodeLine($0.element, at: SourcePosition(fileID: "archive-prefix", byteOffset: Int64($0.offset))).event
        }
        let state = SessionReducer.reduce(full + prefix, owningThreadID: Fixture.threadID)
        XCTAssertEqual(state.context.configuredModel?.model, "other-model")
        XCTAssertEqual(state.context.window, 2000)
        XCTAssertFalse(state.context.footprintIsHistorical)
    }
    func testDifferingWindowCopyInvalidatesOldFootprint() throws {
        let state = SessionReducer.reduce(try Fixture.events("native-two-requests") + Fixture.changedPrefixCopy(),
                                          owningThreadID: Fixture.threadID)
        XCTAssertTrue(state.context.footprintIsHistorical)
        XCTAssertNil(state.context.lastRequestRatio)
    }
    func testDifferingModelCopiesDoNotChooseConfiguredAttribution() throws {
        let state = SessionReducer.reduce(try Fixture.events("native-two-requests") + Fixture.changedPrefixCopy(model: true),
                                          owningThreadID: Fixture.threadID)
        XCTAssertNil(state.context.configuredModel)
        XCTAssertNil(state.requests.first?.configuredModel)
        XCTAssertTrue(state.context.footprintIsHistorical)
        XCTAssertNil(state.context.window)
    }
    func testModelChangeRecoversWithFreshNativeAndMatchingCapacity() throws {
        let state = try reduce("model-change-fresh-request")
        XCTAssertEqual(state.context.configuredModel?.model, "other-model")
        XCTAssertEqual(state.context.window, 2000)
        XCTAssertFalse(state.context.footprintIsHistorical)
        XCTAssertEqual(state.context.lastRequestRatio, 0.03)
        XCTAssertEqual(state.requests.first?.configuredModel?.model, "example-model")
        XCTAssertEqual(state.requests.last?.configuredModel?.model, "other-model")
    }
    func testWindowKeepsTaskAndSourceProvenance() throws {
        let state = try reduce("native-two-requests")
        XCTAssertEqual(state.context.windowEvidence?.taskID, "task-a")
        XCTAssertEqual(state.context.windowEvidence?.source.fileID, "native-two-requests")
        XCTAssertEqual(state.context.windowEvidence?.configuredModel?.model, "example-model")
        XCTAssertFalse(state.context.configuredModelIsHistorical)
    }
    func testCompactionMarksConfiguredModelHistorical() throws {
        let events = try Fixture.events("compaction-checkpoint")
        let state = SessionReducer.reduce(Array(events.dropLast()), owningThreadID: Fixture.threadID)
        XCTAssertTrue(state.context.configuredModelIsHistorical)
        XCTAssertNil(state.context.windowEvidence)
    }
    private func reduce(_ name: String) throws -> DerivedSession {
        SessionReducer.reduce(try Fixture.events(name), owningThreadID: Fixture.threadID)
    }
}
