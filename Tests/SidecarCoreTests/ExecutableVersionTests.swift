import XCTest
import Darwin
@testable import SidecarCore

final class ExecutableVersionTests: XCTestCase, @unchecked Sendable {
    func testChosenExecutableUsesChosenRootAndOnlyNumericVersionIsRetained() async throws {
        let f = try ReaderFixture()
        let executable = try f.write(Data("#!/bin/sh\n[ \"$CODEX_HOME\" = \"$EXPECTED_ROOT\" ] || exit 7\n[ \"$1\" = \"--version\" ] || exit 8\nprintf 'codex-cli 9.8.7-synthetic\\n'\n".utf8), "version probe")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let version = await ExecutableVersion.verify(executable, root: f.root, environment: ["EXPECTED_ROOT": f.root.path])
        XCTAssertEqual(version, "9.8.7-synthetic")
        try Data("#!/bin/sh\nprintf 'private unknown text\\n'\n".utf8).write(to: executable)
        let invalid = await ExecutableVersion.verify(executable, root: f.root, environment: [:])
        XCTAssertNil(invalid)
    }
    func testCancellationStopsOwnedUnresponsiveVersionProbe() async throws {
        let f = try ReaderFixture()
        let executable = try f.write(Data("#!/usr/bin/perl\nopen(F, '>', $ENV{CODEX_HOME}.'/probe.pid'); print F $$; close F; $SIG{TERM}=sub {}; while(1) { select undef,undef,undef,0.01; }\n".utf8), "unresponsive probe")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let root = f.root
        let task = Task { await ExecutableVersion.verify(executable, root: root, environment: [:]) }
        let pidFile = root.appendingPathComponent("probe.pid")
        for _ in 0..<200 { if FileManager.default.fileExists(atPath: pidFile.path) { break }; try await Task.sleep(for: .milliseconds(5)) }
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        let began = ProcessInfo.processInfo.systemUptime
        task.cancel()
        let version = await task.value
        XCTAssertNil(version)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 1)
        XCTAssertEqual(kill(pid, 0), -1)
    }
    func testOfflineLiveRuntimeDoesNotStartQuotaTransportForUnverifiedExecutable() async throws {
        let f = try ReaderFixture()
        let executable = try f.write(Data("#!/bin/sh\nprintf 'codex-cli 9.8.7-synthetic\\n'\n".utf8), "fake codex")
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath: executable.path)
        let runtime = await SidecarRuntime.live(LocalSettings(rootOverride: f.root.path, executableOverride: executable.path, offline: true))
        XCTAssertEqual(runtime.root, f.root)
        XCTAssertTrue(runtime.compatibility.contains("9.8.7-synthetic"))
        XCTAssertTrue(runtime.compatibility.contains("Unvalidated"))
        let stream = await runtime.quotas.snapshots()
        var iterator = stream.makeAsyncIterator()
        await runtime.quotas.start()
        let value = await iterator.next()
        XCTAssertEqual(value, .unavailable(.offline))
        await runtime.stop()
    }
}
