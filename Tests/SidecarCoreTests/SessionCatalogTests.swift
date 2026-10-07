import XCTest
@testable import SidecarCore

final class SessionCatalogTests: XCTestCase, @unchecked Sendable {
    func testInjectedRootPrecedence() throws {
        let fixture = try ReaderFixture()
        let home = fixture.root.appendingPathComponent("home")
        let env = fixture.root.appendingPathComponent("env")
        XCTAssertEqual(SessionCatalog.resolveRoot(override: fixture.root, environment: ["CODEX_HOME": env.path], userHome: home), fixture.root)
        XCTAssertEqual(SessionCatalog.resolveRoot(override: nil, environment: ["CODEX_HOME": env.path], userHome: home).path, env.path)
        XCTAssertEqual(SessionCatalog.resolveRoot(override: nil, environment: [:], userHome: home).path, home.appendingPathComponent(".codex").path)
    }
    func testDiscoveryDuplicatesArchivesAndProvenance() async throws {
        let f = try ReaderFixture()
        try f.write(ReaderFixture.header(), "sessions/a.jsonl")
        try f.write(ReaderFixture.header(), "archived_sessions/copy.jsonl")
        try f.write(ReaderFixture.header("child", parent: Fixture.threadID), "sessions/child.jsonl")
        let catalog = SessionCatalog()
        let sessions = await catalog.discover(root: f.root)
        XCTAssertEqual(sessions.count, 2)
        let root = try XCTUnwrap(sessions.first { $0.id == Fixture.threadID })
        XCTAssertEqual(root.sourceURLs.count, 2)
        XCTAssertEqual(root.projectName, "example-project")
        XCTAssertEqual(root.cliVersion, "0.160.1")
        XCTAssertEqual(sessions.first { $0.id == "child" }?.parentThreadID, Fixture.threadID)
        let active = await SessionCatalog(includeArchives: false).discover(root: f.root)
        XCTAssertEqual(active.first { $0.id == Fixture.threadID }?.sourceURLs.count, 1)
    }
    func testMissingUnreadableAndSymlinkEscape() async throws {
        let f = try ReaderFixture(); let outside = try ReaderFixture()
        let target = try outside.write(ReaderFixture.header())
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("sessions/escape.jsonl"), withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("sessions/escape-dir"), withDestinationURL: outside.root)
        let catalog = SessionCatalog()
        let escaped = await catalog.discover(root: f.root)
        XCTAssertTrue(escaped.isEmpty)
        let missing = await catalog.discover(root: f.root.appendingPathComponent("missing"))
        XCTAssertTrue(missing.isEmpty)
        let awaited1 = await catalog.lastStatus
        XCTAssertEqual(awaited1, .missingRoot)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: f.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.root.path) }
        let unreadable = await catalog.discover(root: f.root)
        XCTAssertTrue(unreadable.isEmpty)
        let awaited2 = await catalog.lastStatus
        XCTAssertEqual(awaited2, .unreadableRoot)
    }
    func testArchiveMoveAndInvalidInitialHeader() async throws {
        let f = try ReaderFixture()
        let source = try f.write(ReaderFixture.header())
        try f.write(Data("bad\n".utf8) + ReaderFixture.header("late"), "sessions/invalid.jsonl")
        let catalog = SessionCatalog()
        let awaited3 = (await catalog.discover(root: f.root))
        XCTAssertEqual(awaited3.count, 1)
        let destination = f.root.appendingPathComponent("archived_sessions/moved.jsonl")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination)
        let sessions = await catalog.discover(root: f.root)
        XCTAssertEqual(sessions.count, 1); XCTAssertEqual(sessions[0].sourceURLs.count, 1)
        XCTAssertEqual(sessions[0].sourceURLs[0].lastPathComponent, "moved.jsonl")
        XCTAssertEqual(sessions[0].sourceURLs[0].deletingLastPathComponent().lastPathComponent, "archived_sessions")
    }
    func testMeasuredFiveSecondDiscoveryFallbackAndStop() async throws {
        let f = try ReaderFixture()
        let catalog = SessionCatalog(watcherHints: false)
        let stream = await catalog.sessions(root: f.root)
        let initial = expectation(description: "Initial empty catalog")
        let discovered = expectation(description: "Directory reconciliation finds new session")
        let start = Date()
        let consumer = Task {
            var first = true
            for await sessions in stream {
                if first { initial.fulfill(); first = false }
                if sessions.contains(where: { $0.id == Fixture.threadID }) {
                    discovered.fulfill(); return Date().timeIntervalSince(start)
                }
            }
            return Double.infinity
        }
        await fulfillment(of: [initial], timeout: 1)
        try f.write(ReaderFixture.native(10000), "sessions/nested/new.jsonl")
        await fulfillment(of: [discovered], timeout: 6)
        consumer.cancel()
        let seconds = await consumer.value
        XCTAssertLessThanOrEqual(seconds, 6)
        await catalog.stop()
        print("STAGE3_MEASURE discovery_stat_seconds=\(seconds)")
    }
    func testUnreadableSessionDirectoryIsReported() async throws {
        let f = try ReaderFixture()
        let folder = f.root.appendingPathComponent("sessions")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        let catalog = SessionCatalog()
        let found = await catalog.discover(root: f.root)
        XCTAssertTrue(found.isEmpty)
        let status = await catalog.lastStatus
        XCTAssertEqual(status, .partial)
    }

    func testOversizedFirstRecordCannotDiscoverLaterHeader() async throws {
        let f = try ReaderFixture()
        try f.write(Data(repeating: 65, count: 8 * 1024 * 1024 + 1) + Data([10]) + ReaderFixture.header())
        let catalog = SessionCatalog()
        let sessions = await catalog.discover(root: f.root)
        XCTAssertTrue(sessions.isEmpty)
        let status = await catalog.lastStatus
        XCTAssertEqual(status, .partial)
    }
    func testObsoleteCatalogScanCannotOverwriteNewRootStatus() async throws {
        let f = try ReaderFixture()
        let padding = String(repeating: "a", count: 7 * 1024 * 1024)
        let header = Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"old\",\"ignored\":\"\(padding)\"}}\n".utf8)
        for index in 0..<5 { try f.write(header, "sessions/\(index).jsonl") }
        let catalog = SessionCatalog(watcherHints: false)
        let oldStream = await catalog.sessions(root: f.root)
        let oldConsumer = Task { for await _ in oldStream {} }
        try await Task.sleep(for: .milliseconds(10))
        let missing = f.root.appendingPathComponent("missing")
        let stream = await catalog.sessions(root: missing)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertTrue(first?.isEmpty == true)
        try await Task.sleep(for: .milliseconds(600))
        let status = await catalog.lastStatus
        XCTAssertEqual(status, .missingRoot)
        oldConsumer.cancel(); await oldConsumer.value; await catalog.stop()
    }
    func testSourceOpenRejectsParentSymlinkRaces() async throws {
        let f = try ReaderFixture(); let outside = try ReaderFixture()
        let parent = f.root.appendingPathComponent("sessions/parent")
        let parked = f.root.appendingPathComponent("sessions/parked")
        let url = try f.write(Data([0]), "sessions/parent/file.jsonl")
        try outside.write(Data([1]), "sessions/file.jsonl")
        let target = outside.root.appendingPathComponent("sessions")
        let writer = Task.detached {
            for _ in 0..<2000 {
                try? FileManager.default.moveItem(at: parent, to: parked)
                try? FileManager.default.createSymbolicLink(at: parent, withDestinationURL: target)
                try? FileManager.default.removeItem(at: parent)
                try? FileManager.default.moveItem(at: parked, to: parent)
            }
        }
        var escaped = 0, opened = 0
        for _ in 0..<4000 {
            guard let handle = try? SourceAccess.openFile(url) else { continue }
            opened += 1
            let data = try? handle.read(upToCount: 1)
            try? handle.close()
            if data == Data([1]) { escaped += 1 }
        }
        await writer.value
        XCTAssertEqual(escaped, 0)
        XCTAssertGreaterThan(opened, 0)
    }

    func testRootsPrecedeChildrenAndConflictingProvenanceIsAmbiguous() async throws {
        let f = try ReaderFixture()
        try f.write(ReaderFixture.header("z-root"), "sessions/root.jsonl")
        try f.write(ReaderFixture.header("a-child", parent: "z-root"), "sessions/child.jsonl")
        try f.write(ReaderFixture.header("conflict"), "sessions/copy-a.jsonl")
        try f.write(ReaderFixture.header("conflict", parent: "parent"), "sessions/copy-b.jsonl")
        let sessions = await SessionCatalog().discover(root: f.root)
        XCTAssertLessThan(sessions.firstIndex { $0.id == "z-root" }!, sessions.firstIndex { $0.id == "a-child" }!)
        let ambiguous = try XCTUnwrap(sessions.first { $0.id == "conflict" })
        XCTAssertTrue(ambiguous.provenanceAmbiguous)
        XCTAssertNil(ambiguous.parentThreadID)
        var selection = SessionSelection(); selection.update([ambiguous])
        XCTAssertNil(selection.mostRecentSuggestion)
    }

    func testOlderConcurrentDiscoveryCannotChangeNewerStatus() async throws {
        let f = try ReaderFixture()
        let padding = String(repeating: "a", count: 7 * 1024 * 1024)
        let header = Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"old\",\"ignored\":\"\(padding)\"}}\n".utf8)
        for index in 0..<5 { try f.write(header, "sessions/\(index).jsonl") }
        let catalog = SessionCatalog(watcherHints: false)
        let old = Task { await catalog.discover(root: f.root) }
        try await Task.sleep(for: .milliseconds(10))
        _ = await catalog.discover(root: f.root.appendingPathComponent("missing"))
        _ = await old.value
        let status = await catalog.lastStatus
        XCTAssertEqual(status, .missingRoot)
        await catalog.stop()
    }

}
