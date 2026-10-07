import XCTest
@testable import SidecarCore

final class SessionSelectionTests: XCTestCase {
    func descriptor(_ id: String, time: Double?, parent: String? = nil) -> SessionDescriptor {
        .init(id: id, sourceURLs: [], projectName: nil, cliVersion: nil, lastActivity: time.map(Date.init(timeIntervalSince1970:)), parentThreadID: parent)
    }
    func testManualPinSurvivesNewChildConcurrentRootAndDeletion() {
        var selection = SessionSelection()
        selection.pin("root")
        selection.update([descriptor("root", time: 1), descriptor("child", time: 3, parent: "root"), descriptor("other", time: 2)])
        XCTAssertEqual(selection.pinnedID, "root")
        XCTAssertEqual(selection.mostRecentSuggestion?.id, "other")
        selection.update([descriptor("other", time: 4)])
        XCTAssertEqual(selection.pinnedID, "root")
    }
    func testTiesAndMissingActivityAreAmbiguousNotForegroundIdentity() {
        var selection = SessionSelection()
        selection.update([descriptor("a", time: 2), descriptor("b", time: 2), descriptor("child", time: 5, parent: "a")])
        XCTAssertNil(selection.mostRecentSuggestion)
        XCTAssertEqual(Set(selection.recentCandidates.map(\.id)), ["a", "b"])
        selection.update([descriptor("a", time: nil)])
        XCTAssertNil(selection.mostRecentSuggestion)
        XCTAssertNil(selection.pinnedID)
    }
}
