import XCTest
@testable import SidecarCore

final class ToolAssociatorTests: XCTestCase {
    func testOrderedCallsAndCompletedMirrorsCountOnce() throws {
        let state = try reduce("tools-ordered")
        XCTAssertEqual(state.requests.map { $0.tools.count }, [1, 1])
        XCTAssertEqual(try XCTUnwrap(state.requests.first?.tools.first).name, "functions.exec")
        XCTAssertTrue(try XCTUnwrap(state.requests.first?.tools.first).outputReceived)
        XCTAssertEqual(try XCTUnwrap(state.requests.last?.tools.first).kind, .custom)
        XCTAssertTrue(state.unattributedTools.isEmpty)
    }
    func testLateOutputUpdatesExistingAssociatedCall() throws {
        let state = try reduce("tools-late-output")
        XCTAssertEqual(try XCTUnwrap(state.requests.first).tools.count, 1)
        XCTAssertTrue(try XCTUnwrap(state.requests.first?.tools.first).outputReceived)
    }
    func testOrphanAndUnknownOutputRemainUnattributed() throws {
        let state = try reduce("tools-orphaned")
        XCTAssertTrue(try XCTUnwrap(state.requests.first).tools.isEmpty)
        XCTAssertEqual(state.unattributedTools.count, 2)
    }
    func testTaskBoundaryDoesNotMoveOldCallToNewRequest() throws {
        let state = try reduce("tools-task-boundary")
        XCTAssertTrue(try XCTUnwrap(state.requests.first).tools.isEmpty)
        XCTAssertEqual(state.unattributedTools.count, 1)
    }
    func testConcurrentTasksPreserveAmbiguity() throws {
        let state = try reduce("tools-concurrent")
        XCTAssertTrue(try XCTUnwrap(state.requests.first).tools.isEmpty)
        XCTAssertEqual(state.unattributedTools.count, 1)
    }
    func testInterruptedCallDoesNotBecomeRequest() throws {
        let state = try reduce("interrupted-no-usage")
        XCTAssertTrue(state.requests.isEmpty)
        XCTAssertEqual(state.unattributedTools.count, 1)
    }
    func testForeignResponseStillBreaksAssociationSegment() throws {
        let state = try reduce("foreign-tool-boundary")
        XCTAssertEqual(state.requests.count, 1)
        XCTAssertTrue(try XCTUnwrap(state.requests.first).tools.isEmpty)
        XCTAssertEqual(state.unattributedTools.count, 1)
    }
    func testConflictingCallMetadataRemainsAmbiguous() throws {
        let state = try reduce("tool-conflicting-name")
        XCTAssertTrue(try XCTUnwrap(state.requests.first).tools.isEmpty)
        XCTAssertTrue(try XCTUnwrap(state.unattributedTools.first).isAmbiguous)
    }
    func testOutputBeforeCallCannotEstablishAssociation() throws {
        let state = try reduce("tool-output-before-call")
        XCTAssertTrue(try XCTUnwrap(state.requests.first).tools.isEmpty)
        XCTAssertEqual(state.unattributedTools.count, 1)
    }
    func testCopiesDisagreeingOnOrderInvalidateAssociation() throws {
        let events = try Fixture.events("tool-reversed-copy-a") + Fixture.events("tool-reversed-copy-b")
        let state = SessionReducer.reduce(events, owningThreadID: Fixture.threadID)
        XCTAssertEqual(state.totals.total, 180)
        XCTAssertTrue(state.requests.allSatisfy { $0.tools.isEmpty })
        XCTAssertEqual(state.unattributedTools.count, 1)
    }
    private func reduce(_ name: String) throws -> DerivedSession {
        SessionReducer.reduce(try Fixture.events(name), owningThreadID: Fixture.threadID)
    }
}
