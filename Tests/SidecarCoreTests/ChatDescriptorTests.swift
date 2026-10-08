import XCTest
@testable import SidecarCore

final class ChatDescriptorTests: XCTestCase {
    private func chat(_ id: String, title: String?) -> SessionDescriptor {
        .init(id: id, sourceURLs: [], projectName: "Synthetic project", cliVersion: nil,
              lastActivity: nil, parentThreadID: nil, title: title)
    }
    // Breaks if the title is hidden behind opaque identity or extra identity is always appended.
    func testUniqueStoredTitleReplacesIdentity() {
        let a = chat("samepref-long-id-0001", title: "Synthetic name")
        let label = PresentationText.descriptor(a, peers: [a])
        XCTAssertTrue(label.hasPrefix("Synthetic project · Synthetic name · Root"))
        XCTAssertFalse(label.contains("samepref"))
    }
    // Breaks if identical title/project rows become indistinguishable while their Picker tags differ.
    func testDuplicateStoredTitlesRemainDistinguishable() {
        let a = chat("samepref-long-id-0001", title: "Same name")
        let b = chat("samepref-long-id-0002", title: "Same name")
        let first = PresentationText.descriptor(a, peers: [a, b])
        let second = PresentationText.descriptor(b, peers: [a, b])
        XCTAssertTrue(first.contains("Same name")); XCTAssertTrue(second.contains("Same name"))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.contains("0001")); XCTAssertTrue(second.contains("0002"))
    }
    // Breaks if fallback truncates every migrated UUID to the same eight characters.
    func testMissingTitleWithCollidingIDPrefixesRemainsDistinguishable() {
        let a = chat("samepref-long-id-0001", title: nil)
        let b = chat("samepref-long-id-0002", title: nil)
        XCTAssertNotEqual(PresentationText.descriptor(a, peers: [a, b]), PresentationText.descriptor(b, peers: [a, b]))
        XCTAssertTrue(PresentationText.descriptor(a, peers: [a, b]).contains("0001"))
    }
    func testLargeSharedPrefixCatalogProducesUniqueLabelsWithinBudget() {
        let chats = (0..<10000).map { chat("samepref-long-id-" + String(format: "%05d", $0), title: "Same name") }
        let start = Date()
        let labels = PresentationText.descriptors(chats)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(labels.count, 10000)
        XCTAssertEqual(Set(labels.values).count, 10000)
        XCTAssertLessThan(elapsed, 2, "Whole-catalog labels must avoid quadratic row-by-row scans")
        print("SELECTOR_MEASURE labels=10000 seconds=\(elapsed)")
    }

}
