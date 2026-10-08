import XCTest
@testable import SidecarCore

actor QuotaWireFake: QuotaWire {
    nonisolated let events: AsyncStream<QuotaWireEvent>
    nonisolated let continuation: AsyncStream<QuotaWireEvent>.Continuation
    var writes: [Data] = []
    var starts = 0; var stops = 0
    init() { (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64)) }
    func start() async throws { starts += 1 }
    func write(_ bytes: Data) async throws { writes.append(bytes) }
    func stop() async { stops += 1; continuation.finish() }
    func send(_ value: String) { continuation.yield(.stdout(quotaBytes(value + "\n"))) }
    func packets() -> [[String: Any]] { writes.compactMap { try? QuotaDecoder.dictionary($0) } }
    func requestID(_ method: String) -> Int? { packets().last { $0["method"] as? String == method }?["id"] as? Int }
}
final class QuotaRPCTests: XCTestCase, @unchecked Sendable {
    func testInterleavedIDsNotificationsAndUnsupportedRequests() async throws {
        let wire = QuotaWireFake(); let clock = QuotaTestClock(); let rpc = QuotaRPC(wire: wire, scheduler: clock)
        let a = Task { try await rpc.request(method: "account/read", params: quotaBytes(#"{"refreshToken":false}"#)) }
        let b = Task { try await rpc.request(method: "account/rateLimits/read", params: quotaBytes(#"{"excludeResetCreditDetails":true}"#)) }
        await quotaEventually { await wire.writes.count == 2 }
        let aid = await wire.requestID("account/read")!, bid = await wire.requestID("account/rateLimits/read")!
        await wire.send("{\"id\":\(bid),\"result\":{\"value\":2}}")
        await wire.send(#"{"method":"account/rateLimits/updated","params":{"rateLimits":{}}}"#)
        await wire.send(#"{"method":"ignored","params":{"private":"PRIVATE_MARKER"}}"#)
        await wire.send(#"{"id":"server-request","method":"approval","params":{"private":"PRIVATE_MARKER"}}"#)
        await wire.send("{\"id\":\(aid),\"result\":{\"value\":1}}")
        let av = try await a.value, bv = try await b.value
        XCTAssertEqual(try QuotaDecoder.dictionary(av)["value"] as? Int, 1)
        XCTAssertEqual(try QuotaDecoder.dictionary(bv)["value"] as? Int, 2)
        var iterator = rpc.notifications().makeAsyncIterator()
        let hint = await iterator.next()
        XCTAssertEqual(try QuotaDecoder.dictionary(try XCTUnwrap(hint))["method"] as? String, "account/rateLimits/updated")
        await quotaEventually { await wire.writes.count == 3 }
        let packets = await wire.writes
        XCTAssertFalse(packets.contains { String(decoding: $0, as: UTF8.self).contains("PRIVATE_MARKER") })
        let response = try QuotaDecoder.dictionary(packets.last!)
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32601)
        await rpc.stop()
    }
    func testAllowlistRejectsUnsafeMethodsAndParamsBeforeStarting() async {
        let wire = QuotaWireFake(); let rpc = QuotaRPC(wire: wire)
        for method in ["turn/start", "thread/resume", "account/logout", "approval", "account/login/start"] {
            do { _ = try await rpc.request(method: method, params: nil); XCTFail("Unsafe method accepted") }
            catch { XCTAssertEqual(error as? QuotaFailure, .unsupportedProtocol) }
        }
        for (method, params) in [("account/read", #"{"refreshToken":true}"#), ("account/rateLimits/read", #"{"supportsLunaReserve":true}"#)] {
            do { _ = try await rpc.request(method: method, params: quotaBytes(params)); XCTFail("Unsafe params accepted") }
            catch { XCTAssertEqual(error as? QuotaFailure, .unsupportedProtocol) }
        }
        let starts = await wire.starts; XCTAssertEqual(starts, 0); await rpc.stop()
    }
    func testTimeoutCancellationMalformedAndProcessExitAreSanitized() async {
        for reason in [QuotaFailure.timeout, .malformedReply, .processExited, .requestFailed, .cancelled] {
            let wire = QuotaWireFake(); let clock = QuotaTestClock(); let rpc = QuotaRPC(wire: wire, scheduler: clock)
            let task = Task { try await rpc.request(method: "account/read", params: quotaBytes(#"{"refreshToken":false}"#)) }
            await quotaEventually { await wire.writes.count == 1 && clock.sleepers > 0 }
            let id = await wire.requestID("account/read")!
            switch reason {
            case .timeout: clock.advance(20)
            case .malformedReply: await wire.send("PRIVATE_MARKER")
            case .processExited: wire.continuation.yield(.exited)
            case .cancelled: task.cancel()
            default: await wire.send("{\"id\":\(id),\"error\":{\"message\":\"PRIVATE_MARKER\"}}")
            }
            do { _ = try await task.value; XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? QuotaFailure, reason); XCTAssertFalse(String(describing: error).contains("PRIVATE_MARKER")) }
            await rpc.stop()
        }
    }
    func testExecutableResolutionAndChildConfiguration() throws {
        let root = URL(fileURLWithPath: "/synthetic/home")
        let config = QuotaProcessConfiguration(executable: URL(fileURLWithPath: "/synthetic/codex"), root: root, environment: ["SAFE":"yes", "CODEX_HOME":"other"])
        XCTAssertEqual(config.environment["CODEX_HOME"], root.path)
        XCTAssertEqual(config.arguments, ["-c", "analytics.enabled=false", "app-server", "--listen", "stdio://"])
        XCTAssertNil(QuotaExecutable.resolve(override: nil, environment: ["PATH":""], bundleCandidates: []))
        XCTAssertNil(QuotaExecutable.resolve(override: URL(fileURLWithPath: "/missing"), environment: [:], bundleCandidates: []))
    }
}

extension QuotaRPCTests {
    func testHandshakeHasOnlyPassiveFieldsAndStoppedStreamFinishes() async throws {
        let wire = QuotaWireFake(); let rpc = QuotaRPC(wire: wire)
        let initTask = Task { try await rpc.request(method: "initialize", params: quotaBytes(#"{"clientInfo":{"name":"codex_sidecar","version":"0.1.0"}}"#)) }
        await quotaEventually { await wire.writes.count == 1 }
        let id = await wire.requestID("initialize")!
        await wire.send("{\"id\":\(id),\"result\":{\"userAgent\":\"synthetic\"}}")
        _ = try await initTask.value
        _ = try await rpc.request(method: "initialized", params: nil)
        let writes = await wire.writes
        let packets = try writes.map(QuotaDecoder.dictionary)
        XCTAssertEqual(Set((packets[0]["params"] as? [String: Any])!.keys), ["clientInfo"])
        XCTAssertNil(packets[1]["id"])
        await rpc.stop(); var iterator = rpc.notifications().makeAsyncIterator()
        let next = await iterator.next(); XCTAssertNil(next)
    }
    func testOversizedLineAndMalformedMatchingResultFailClosed() async {
        for line in [String(repeating: "x", count: 1024 * 1024 + 1), #"{"id":1,"result":null}"#, #"{"id":true,"result":{}}"#] {
            let wire = QuotaWireFake(); let rpc = QuotaRPC(wire: wire)
            let task = Task { try await rpc.request(method: "account/read", params: quotaBytes(#"{"refreshToken":false}"#)) }
            await quotaEventually { await wire.writes.count == 1 }
            await wire.send(line)
            do { _ = try await task.value; XCTFail("Malformed reply accepted") }
            catch { XCTAssertEqual(error as? QuotaFailure, .malformedReply) }
            await rpc.stop()
        }
    }
    func testRealOwnedPipesDrainConcurrentOutputAndCleanUp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("synthetic-server")
        let program = #"""
        #!/usr/bin/perl
        use strict; use warnings; use JSON::PP;
        $|=1;
        while (my $line = <STDIN>) {
            my $p = decode_json($line);
            for (1..16) {
                print STDERR ('PRIVATE_MARKER' x 16000);
                print '{"method":"ignored","params":{"private":"', ('PRIVATE_MARKER' x 4000), '"}}', "\n";
            }
            print encode_json({id => $p->{id}, result => {userAgent => 'synthetic', rootMatches => ($ENV{CODEX_HOME} eq $ENV{EXPECTED_ROOT} ? JSON::PP::true : JSON::PP::false)}}), "\n";
        }
        """#
        try program.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let rpc = QuotaRPC(configuration: .init(executable: executable, root: root, environment: ["EXPECTED_ROOT":root.path]))
        let response = try await rpc.request(method: "initialize", params: quotaBytes(#"{"clientInfo":{"name":"codex_sidecar","version":"0.1.0"}}"#))
        XCTAssertEqual(try QuotaDecoder.dictionary(response)["rootMatches"] as? Bool, true)
        XCTAssertFalse(String(decoding: response, as: UTF8.self).contains("PRIVATE_MARKER"))
        let start = Date(); await rpc.stop()
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("auth.json").path))
    }
    func testMissingExecutableIsDistinct() async {
        let rpc = QuotaRPC(configuration: .init(executable: URL(fileURLWithPath: "/missing/codex"), root: URL(fileURLWithPath: "/synthetic"), environment: [:]))
        do { _ = try await rpc.request(method: "initialize", params: quotaBytes(#"{"clientInfo":{"name":"codex_sidecar","version":"0.1.0"}}"#)); XCTFail("Missing executable accepted") }
        catch { XCTAssertEqual(error as? QuotaFailure, .missingExecutable) }
        await rpc.stop()
    }
}

extension QuotaRPCTests {
    func testAccountChangeHintSurvivesQuotaHintFlood() async throws {
        let wire = QuotaWireFake(); let rpc = QuotaRPC(wire: wire)
        let task = Task { try await rpc.request(method: "account/read", params: quotaBytes(#"{"refreshToken":false}"#)) }
        await quotaEventually { await wire.writes.count == 1 }
        await wire.send(#"{"method":"account/updated"}"#)
        for _ in 0..<100 { await wire.send(#"{"method":"account/rateLimits/updated"}"#) }
        let id = await wire.requestID("account/read")!
        await wire.send("{\"id\":\(id),\"result\":{}}")
        _ = try await task.value
        var iterator = rpc.notifications().makeAsyncIterator()
        let hint = await iterator.next()
        XCTAssertEqual(try QuotaDecoder.dictionary(try XCTUnwrap(hint))["method"] as? String, "account/updated")
        await rpc.stop()
    }
    func testOversizedServerRequestIDIsNotReflected() async {
        let wire = QuotaWireFake(); let rpc = QuotaRPC(wire: wire)
        let task = Task { try await rpc.request(method: "account/read", params: quotaBytes(#"{"refreshToken":false}"#)) }
        await quotaEventually { await wire.writes.count == 1 }
        await wire.send("{\"id\":\"" + String(repeating: "x", count: 262144) + "\",\"method\":\"unknown\"}")
        // Complete outstanding request so the old implementation fails without hanging.
        await wire.send(#"{"id":1,"result":{}}"#)
        do { _ = try await task.value; XCTFail("Oversized server ID accepted") }
        catch { XCTAssertEqual(error as? QuotaFailure, .malformedReply) }
        let writes = await wire.writes; XCTAssertFalse(writes.contains { $0.count > 1024 })
        await rpc.stop()
    }
}

extension QuotaRPCTests {
    func testNonreadingChildCannotBlockStopAndWriterIsBounded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("nonreading-child")
        try "#!/usr/bin/perl\n$|=1; print qq(ready\\n); $SIG{TERM}=sub { exit 0 }; while(1) { select undef,undef,undef,0.01; }\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath: executable.path)
        let wire = ProcessQuotaWire(.init(executable: executable, root: root, environment: [:]))
        try await wire.start()
        var iterator = wire.events.makeAsyncIterator(); _ = await iterator.next()
        let results = QuotaWriteResults()
        let jobs = (0..<256).map { _ in Task {
            do { try await wire.write(Data(repeating: 65, count: 1024)); await results.record(nil) }
            catch { await results.record(error as? QuotaFailure) }
        } }
        // Queue saturation proves we reached pipe backpressure, without a real sleep.
        await quotaEventually { await results.reasons.contains(.malformedReply) }
        let start = Date(); await wire.stop()
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        for job in jobs { await job.value }
        let count = await results.count; XCTAssertEqual(count, 256)
    }
    func testClosedChildStdinDoesNotSendSIGPIPEToHost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("closed-input-child")
        try "#!/usr/bin/perl\nclose STDIN; $|=1; print qq(ready\\n); while(1) { select undef,undef,undef,0.01; }\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath: executable.path)
        let wire = ProcessQuotaWire(.init(executable: executable, root: root, environment: [:]))
        try await wire.start(); var iterator = wire.events.makeAsyncIterator(); _ = await iterator.next()
        do { try await wire.write(quotaBytes("synthetic\n")); XCTFail("Closed pipe accepted") }
        catch { XCTAssertEqual(error as? QuotaFailure, .processExited) }
        await wire.stop()
    }
}
private actor QuotaWriteResults {
    var count = 0
    var reasons: [QuotaFailure] = []
    func record(_ reason: QuotaFailure?) { count += 1; if let reason { reasons.append(reason) } }
}
