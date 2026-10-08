import XCTest
@testable import SidecarCore

final class SessionCatalogMetadataTests: XCTestCase, @unchecked Sendable {
    // Breaks if ID ordering wins over activity, or children jump ahead of root chats.
    func testRecentRootsFirstThenChildrenWithStableTies() async throws {
        let f = try ReaderFixture()
        for (id, time, parent) in [("a-old", 100.0, nil), ("z-new", 200.0, nil),
                                   ("b-tie", 100.0, nil), ("child", 300.0, "z-new")] {
            let url = try f.write(ReaderFixture.header(id, parent: parent), "sessions/\(id).jsonl")
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: url.path)
        }
        let sessions = await SessionCatalog().discover(root: f.root)
        XCTAssertEqual(sessions.map(\.id), ["z-new", "a-old", "b-tie", "child"])
    }

    // Breaks if metadata is ignored, wrong ownership is joined, or stale entries replace newer names.
    func testIndexTitlesAndMetadataRecencyUseLatestValidEntry() async throws {
        let f = try ReaderFixture()
        for id in ["a-old", "z-recent"] {
            let url = try f.write(ReaderFixture.header(id), "sessions/\(id).jsonl")
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: url.path)
        }
        try f.write(Data("""
        {"id":"a-old","thread_name":"Old chat","updated_at":"2026-01-01T00:00:00Z"}
        {"id":"z-recent","thread_name":"Renamed chat","updated_at":"2026-02-01T00:00:00.123Z","content":"PRIVATE_MARKER"}
        {"id":"z-recent","thread_name":"Obsolete name","updated_at":"2026-01-01T00:00:00Z"}
        {"id":"not-discovered","thread_name":"PRIVATE_MARKER","updated_at":"2026-03-01T00:00:00Z"}

        """.utf8), "session_index.jsonl")
        let sessions = await SessionCatalog().discover(root: f.root)
        XCTAssertEqual(sessions.map(\.id), ["z-recent", "a-old"])
        let label = PresentationText.descriptor(try XCTUnwrap(sessions.first))
        XCTAssertTrue(label.contains("example-project · Renamed chat · Root"))
        XCTAssertFalse(String(describing: sessions).contains("PRIVATE_MARKER"))
        XCTAssertEqual(sessions.first?.lastActivity?.timeIntervalSince1970, 1769904000.123)
    }

    // Breaks if malformed/incomplete lines erase valid data or title control characters leak into menu rows.
    func testMalformedIndexAndIncompleteTailDoNotHideChats() async throws {
        let f = try ReaderFixture(); try f.write(ReaderFixture.header("one"))
        try f.write(Data("""
        broken
        {"id":"one","thread_name":"  Synthetic\\nname  ","updated_at":"2026-01-01T00:00:00Z"}
        {"id":"one","thread_name":42,"updated_at":"2026-02-01T00:00:00Z"}
        {"id":"one","thread_name":"incomplete","updated_at":"2026-03-01T00:00:00Z"}
        """.utf8), "session_index.jsonl")
        let catalog = SessionCatalog()
        let found = await catalog.discover(root: f.root)
        XCTAssertEqual(found.count, 1)
        let label = PresentationText.descriptor(try XCTUnwrap(found.first))
        XCTAssertTrue(label.contains("Synthetic name")); XCTAssertFalse(label.contains("incomplete"))
        let status = await catalog.lastStatus
        XCTAssertEqual(status, .available)
    }

    // Breaks if no-title entries fabricate names, fail discovery, or replace newer filesystem activity.
    func testBlankMissingAndUnavailableIndexFallBackToIdentity() async throws {
        let f = try ReaderFixture(); let url = try f.write(ReaderFixture.header("fallback-id"))
        let catalog = SessionCatalog()
        let missing = await catalog.discover(root: f.root)
        XCTAssertTrue(PresentationText.descriptor(try XCTUnwrap(missing.first)).contains("fallback"))
        let current = Date(timeIntervalSince1970: 1800000000)
        try FileManager.default.setAttributes([.modificationDate: current], ofItemAtPath: url.path)
        let index = try f.write(Data("{\"id\":\"fallback-id\",\"thread_name\":\" \",\"updated_at\":\"2026-01-01T00:00:00Z\"}\n".utf8), "session_index.jsonl")
        let blank = await catalog.discover(root: f.root)
        XCTAssertEqual(blank.first?.lastActivity, current)
        XCTAssertTrue(PresentationText.descriptor(try XCTUnwrap(blank.first)).contains("fallback"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: index.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path) }
        let unreadable = await catalog.discover(root: f.root)
        XCTAssertEqual(unreadable.count, 1)
    }

    // Breaks if optional metadata crosses the selected root through a symlink.
    func testIndexSymlinkIsIgnoredAndSourcesStayReadOnly() async throws {
        let f = try ReaderFixture(); let outside = try ReaderFixture()
        let source = try f.write(ReaderFixture.header("one"))
        let data = Data("{\"id\":\"one\",\"thread_name\":\"Outside title\",\"updated_at\":\"2026-01-01T00:00:00Z\"}\n".utf8)
        let target = try outside.write(data, "session_index.jsonl")
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("session_index.jsonl"), withDestinationURL: target)
        let before = try Data(contentsOf: source)
        let found = await SessionCatalog().discover(root: f.root)
        XCTAssertEqual(found.count, 1)
        XCTAssertFalse(PresentationText.descriptor(try XCTUnwrap(found.first)).contains("Outside title"))
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(try Data(contentsOf: target), data)
    }

    // Breaks if periodic discovery caches an obsolete title forever or clears a pin when order changes.
    func testRenameAndNewActivityPreservePinnedIdentity() async throws {
        let f = try ReaderFixture()
        try f.write(ReaderFixture.header("a"), "sessions/a.jsonl")
        try f.write(ReaderFixture.header("b"), "sessions/b.jsonl")
        let catalog = SessionCatalog()
        var selection = SessionSelection(); selection.pin("a")
        selection.update(await catalog.discover(root: f.root))
        try f.write(Data("{\"id\":\"b\",\"thread_name\":\"Updated name\",\"updated_at\":\"2099-01-01T00:00:00Z\"}\n".utf8), "session_index.jsonl")
        let refreshed = await catalog.discover(root: f.root)
        selection.update(refreshed)
        XCTAssertEqual(refreshed.first?.id, "b")
        XCTAssertTrue(PresentationText.descriptor(try XCTUnwrap(refreshed.first)).contains("Updated name"))
        XCTAssertEqual(selection.pinnedID, "a")
    }
    // Breaks if oversized metadata prevents safe ID fallback or exposes unbounded names.
    func testOversizedIndexAndTitleFallBackWithoutHidingChat() async throws {
        let f = try ReaderFixture(); try f.write(ReaderFixture.header("one"))
        let line = "{\"id\":\"one\",\"thread_name\":\"" + String(repeating: "x", count: 4097) + "\"}\n"
        try f.write(Data(line.utf8), "session_index.jsonl")
        let nameTooLong = await SessionCatalog().discover(root: f.root)
        XCTAssertEqual(nameTooLong.count, 1); XCTAssertNil(nameTooLong.first?.title)
        var oversized = Data("{\"id\":\"one\",\"thread_name\":\"Partial name\"}\n".utf8)
        oversized.append(Data(repeating: 32, count: 16 * 1024 * 1024))
        try f.write(oversized, "session_index.jsonl")
        let indexTooLong = await SessionCatalog().discover(root: f.root)
        XCTAssertEqual(indexTooLong.count, 1); XCTAssertNil(indexTooLong.first?.title)
    }

    // Breaks if malformed timestamps erase a rename or equal timestamps pick an earlier line.
    func testEqualTimestampRenameWinsAndInvalidTimestampIsIgnored() async throws {
        let f = try ReaderFixture(); try f.write(ReaderFixture.header("one"))
        try f.write(Data("""
        {"id":"one","thread_name":"Old name","updated_at":"2026-01-01T00:00:00Z"}
        {"id":"one","thread_name":"New name","updated_at":"2026-01-01T00:00:00Z"}
        {"id":"one","thread_name":"Invalid name","updated_at":"invalid"}

        """.utf8), "session_index.jsonl")
        let found = await SessionCatalog().discover(root: f.root)
        XCTAssertEqual(found.first?.title, "New name")
    }

}
