import Foundation
import XCTest
@testable import SidecarCore

final class RolloutDecoderTests: XCTestCase {
    private let position = SourcePosition(fileID: "fixture", byteOffset: 42)
    private func decode(_ json: String) -> DecodeResult {
        RolloutDecoder().decodeLine(Data(json.utf8), at: position)
    }
    private func record(_ usage: String = #"{"total_tokens":120}"#,
                        thread: String = Fixture.threadID, response: String = "response-a",
                        task: String = "task-a") -> String {
        #"{"timestamp":"2026-01-01T12:00:01Z","type":"token_usage_record","payload":{"thread_id":"\#(thread)","session_id":"runtime-a","turn_id":"\#(task)","response_id":"\#(response)","usage":\#(usage)}}"#
    }

    func testSelectiveDecoderKeepsUsageAndDropsText() throws {
        let line = try XCTUnwrap(Fixture.lines("unknown-and-sensitive").first {
            String(decoding: $0, as: UTF8.self).contains("token_usage_record")
        })
        XCTAssertTrue(String(decoding: line, as: UTF8.self).contains("PRIVATE_MARKER"))
        let result = RolloutDecoder().decodeLine(line, at: position)
        guard case .usageRecord(let record) = result.event else { return XCTFail("Expected usage") }
        XCTAssertEqual(record.usage.total, 120)
        XCTAssertEqual(record.usage.cachedInput, 60)
        XCTAssertEqual(record.usage.reasoning, 5)
        XCTAssertEqual(record.source, position)
        XCTAssertEqual(record.key, RequestKey(threadID: Fixture.threadID, responseID: "response-a"))
        XCTAssertEqual(record.taskID, "task-a")
        XCTAssertEqual(record.rootTaskID, "task-a")
        XCTAssertEqual(record.runtimeSessionID, Fixture.threadID)
        XCTAssertNotNil(record.timestamp)
        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertFalse(String(describing: result).contains("PRIVATE_MARKER"))
    }

    func testNativeFixtureSeparatesRecordsAndSnapshots() throws {
        let results = try Fixture.lines("native-two-requests").map {
            RolloutDecoder().decodeLine($0, at: position)
        }
        XCTAssertTrue(results.allSatisfy { $0.diagnostics.isEmpty })
        let records = results.compactMap { result -> UsageRecord? in
            if case .usageRecord(let record) = result.event { return record }; return nil
        }
        XCTAssertEqual(records.map(\.usage.total), [120, 60])
        XCTAssertEqual(records.last?.threadCumulative?.total, 180)
        XCTAssertEqual(records.last?.taskCumulative?.total, 180)
        XCTAssertEqual(results.filter { if case .usageSnapshot = $0.event { return true }; return false }.count, 2)
        guard case .header(let header) = results[0].event else { return XCTFail("Expected header") }
        XCTAssertEqual(header.threadID, Fixture.threadID)
        XCTAssertEqual(header.cliVersion, "0.160.1")
        guard case .configuredModel(let model) = results[2].event else { return XCTFail("Expected model") }
        XCTAssertEqual(model.model, "example-model")
        XCTAssertEqual(model.taskID, "task-a")
    }

    func testMissingNullAndExplicitZeroArePreserved() throws {
        let results = try Fixture.lines("usage-missing-fields").map {
            RolloutDecoder().decodeLine($0, at: position)
        }
        for result in results.prefix(2) {
            guard case .usageRecord(let record) = result.event else { return XCTFail("Expected partial usage") }
            XCTAssertEqual(record.usage.total, 120)
            XCTAssertNil(record.usage.input)
            XCTAssertNil(record.usage.output)
            XCTAssertNil(record.usage.cachedInput)
            XCTAssertNil(record.usage.reasoning)
            XCTAssertNil(record.usage.cacheWriteInput)
        }
        guard case .usageRecord(let zero) = results[2].event else { return XCTFail("Expected zero") }
        XCTAssertEqual(zero.usage, TokenUsage(input: 0, cachedInput: 0, cacheWriteInput: 0,
                                              output: 0, reasoning: 0, total: 0))
    }

    func testInvalidCountersAreQuarantinedWithSanitizedDiagnostics() throws {
        for line in try Fixture.lines("usage-invalid") {
            let result = RolloutDecoder().decodeLine(line, at: position)
            XCTAssertNil(result.event)
            XCTAssertEqual(result.diagnostics.map(\.category), [.invalidCounters])
            XCTAssertEqual(result.diagnostics.first?.byteOffset, 42)
            XCTAssertEqual(result.diagnostics.first?.occurrenceCount, 1)
            XCTAssertFalse(String(describing: result).contains("PRIVATE_MARKER"))
        }
    }

    func testRequiredIdentitiesAreNotInferred() {
        for json in [record(thread: ""), record(response: ""), record(task: ""),
                     record(thread: " "), record(response: " "), record(task: " ")] {
            XCTAssertNil(decode(json).event)
            XCTAssertFalse(decode(json).diagnostics.isEmpty)
        }
        for key in ["thread_id", "response_id", "turn_id"] {
            var envelope = try! JSONSerialization.jsonObject(with: Data(record().utf8)) as! [String: Any]
            var payload = envelope["payload"] as! [String: Any]
            payload.removeValue(forKey: key)
            envelope["payload"] = payload
            let bytes = try! JSONSerialization.data(withJSONObject: envelope)
            XCTAssertNil(RolloutDecoder().decodeLine(bytes, at: position).event)
        }
    }

    func testUnsupportedEnvelopesDoNotCreateNativeUsage() {
        for json in [#"{}"#, #"[]"#, #"{"type":"token_usage_record"}"#,
                     #"{"type":"token_usage_record","payload":null}"#,
                     #"{"type":"token_usage_record","payload":[]}"#,
                     #"{"type":"token_usage_record","payload":{"usage":{"total_tokens":120}}}"#] {
            XCTAssertNil(decode(json).event)
            XCTAssertFalse(decode(json).diagnostics.isEmpty)
        }
        let wrapped = #"{"type":"event_msg","payload":{"type":"token_usage_record","usage":{"total_tokens":120}}}"#
        XCTAssertEqual(decode(wrapped).event, .unknown)
    }

    func testMalformedLineDoesNotPreventNextValidDecode() throws {
        let lines = try Fixture.lines("malformed")
        let bad = RolloutDecoder().decodeLine(lines[0], at: position)
        XCTAssertNil(bad.event)
        XCTAssertEqual(bad.diagnostics.map(\.category), [.malformedRecord])
        XCTAssertFalse(String(describing: bad).contains("PRIVATE_MARKER"))
        guard case .usageRecord = RolloutDecoder().decodeLine(lines[1], at: position).event else {
            return XCTFail("Expected recovery")
        }
    }

    func testUnknownAndTranscriptEventsRetainNoPayloads() throws {
        for line in try Fixture.lines("unknown-and-sensitive") {
            let result = RolloutDecoder().decodeLine(line, at: position)
            XCTAssertTrue(result.diagnostics.isEmpty)
            XCTAssertFalse(String(describing: result).contains("PRIVATE_MARKER"))
        }
        XCTAssertEqual(decode(#"{"type":"future","payload":"PRIVATE_MARKER"}"#).event, .unknown)
    }

    func testToolMetadataIsAllowlisted() throws {
        let lines = try Fixture.lines("unknown-and-sensitive")
        guard case .toolCall(let call) = RolloutDecoder().decodeLine(lines[2], at: position).event else {
            return XCTFail("Expected call")
        }
        XCTAssertEqual(call.callID, "call-private")
        XCTAssertEqual(call.name, "exec")
        XCTAssertEqual(call.namespace, "functions")
        guard case .toolOutput(let output) = RolloutDecoder().decodeLine(lines[3], at: position).event else {
            return XCTFail("Expected output")
        }
        XCTAssertEqual(output.callID, call.callID)
    }

    func testLifecycleAndWindowMetadata() {
        guard case .taskStarted(let task) = decode(#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"task-a","model_context_window":1000}}"#).event else { return XCTFail("Expected start") }
        XCTAssertEqual(task.taskID, "task-a")
        XCTAssertEqual(task.modelContextWindow, 1000)
        guard case .taskFinished = decode(#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"task-a","last_agent_message":"PRIVATE_MARKER"}}"#).event else { return XCTFail("Expected complete") }
        guard case .taskInterrupted = decode(#"{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"task-a","reason":"PRIVATE_MARKER"}}"#).event else { return XCTFail("Expected interruption") }
    }

    func testNullSnapshotInfoStaysUnavailable() {
        guard case .usageSnapshot(let snapshot) = decode(#"{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"secret":"PRIVATE_MARKER"}}}"#).event else { return XCTFail("Expected snapshot") }
        XCTAssertNil(snapshot.lastUsage)
        XCTAssertNil(snapshot.cumulative)
        XCTAssertNil(snapshot.modelContextWindow)
    }

    func testCheckpointDoesNotBecomeUsageRecord() {
        let nested = record().split(separator: "\n").joined()
        let payload = #"{"type":"compacted","payload":{"compaction_response_id":"compact-a","latest_token_usage_record":\#(nested),"replacement_history":"PRIVATE_MARKER"}}"#
        // A checkpoint contains the record payload, not a second rollout envelope.
        let data = try! JSONSerialization.jsonObject(with: Data(record().utf8)) as! [String: Any]
        let nativePayload = try! String(data: JSONSerialization.data(withJSONObject: data["payload"]!), encoding: .utf8)!
        let json = payload.replacingOccurrences(of: nested, with: nativePayload)
        guard case .checkpoint(let checkpoint) = decode(json).event else { return XCTFail("Expected checkpoint") }
        XCTAssertEqual(checkpoint.latestUsageRecord?.usage.total, 120)
        XCTAssertEqual(checkpoint.responseID, "compact-a")
        XCTAssertFalse(String(describing: decode(json)).contains("PRIVATE_MARKER"))
    }

    func testItemCompletedUsesOnlyNestedToolMetadata() {
        let result = decode(#"{"type":"event_msg","payload":{"type":"item_completed","thread_id":"invented-thread","turn_id":"task-a","item":{"type":"custom_tool_call","call_id":"call-a","name":"example","input":"PRIVATE_MARKER"}}}"#)
        guard case .toolCall(let call) = result.event else { return XCTFail("Expected call") }
        XCTAssertEqual(call.taskID, "task-a")
        XCTAssertEqual(call.threadID, "invented-thread")
        XCTAssertFalse(String(describing: result).contains("PRIVATE_MARKER"))
    }

    func testInvalidCounterTypesAndCumulativeValuesAreRejected() {
        for counter in [#""120""#, "true", "120.5", "9223372036854775808"] {
            XCTAssertEqual(decode(record(#"{"total_tokens":\#(counter)}"#)).diagnostics.map(\.category), [.invalidCounters])
        }
        let invalid = record().replacingOccurrences(of: #""usage":{"total_tokens":120}"#,
            with: #""usage":{"total_tokens":120},"thread_token_usage":{"total_tokens":-1}"#)
        XCTAssertEqual(decode(invalid).diagnostics.map(\.category), [.invalidCounters])
    }
}
