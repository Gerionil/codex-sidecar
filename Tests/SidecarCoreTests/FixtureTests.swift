import XCTest
@testable import SidecarCore

final class FixtureTests: XCTestCase {
    func testSyntheticResourcesAreBundled() throws {
        XCTAssertEqual(try Fixture.lines("native-two-requests").count, 9)
        XCTAssertEqual(try Fixture.lines("malformed").count, 2)
    }
}
