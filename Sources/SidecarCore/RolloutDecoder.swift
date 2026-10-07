import Foundation

/// Decodes one complete record. Framing and file ownership belong to later stages.
public struct RolloutDecoder: Sendable {
    public init() {}

    public func decodeLine(_ bytes: Data, at position: SourcePosition) -> DecodeResult {
        guard bytes.count <= 8 * 1024 * 1024 else {
            return failure(.oversizedRecord, at: position)
        }
        do {
            let decoder = JSONDecoder()
            decoder.userInfo[.sourcePosition] = position
            let event = try decoder.decode(Envelope.self, from: bytes).event
            return DecodeResult(event: event, diagnostics: [])
        } catch let error as ParseFailure {
            return failure(error.category, at: position)
        } catch {
            // Never expose DecodingError descriptions, coding paths, or raw bytes.
            return failure(.malformedRecord, at: position)
        }
    }

    private func failure(_ category: SanitizedDiagnostic.Category,
                         at position: SourcePosition) -> DecodeResult {
        DecodeResult(event: nil, diagnostics: [SanitizedDiagnostic(
            category: category, byteOffset: position.byteOffset)])
    }
}

private extension CodingUserInfoKey {
    static let sourcePosition = CodingUserInfoKey(rawValue: "sourcePosition")!
}

private struct ParseFailure: Error {
    let category: SanitizedDiagnostic.Category
}

/// Only keys with metric semantics are accessed. Unknown values are never modeled.
private enum Field: String, CodingKey {
    case type, payload, timestamp, id, model, name, namespace, item, info, usage
    case sessionID = "session_id", threadID = "thread_id", turnID = "turn_id"
    case rootTurnID = "root_turn_id", responseID = "response_id"
    case cliVersion = "cli_version", parentThreadID = "parent_thread_id"
    case callID = "call_id", window = "model_context_window"
    case taskCumulative = "turn_token_usage", threadCumulative = "thread_token_usage"
    case lastUsage = "last_token_usage", cumulative = "total_token_usage"
    case compactionResponseID = "compaction_response_id"
    case latestRecord = "latest_token_usage_record"
    case input = "input_tokens", cachedInput = "cached_input_tokens"
    case cacheWriteInput = "cache_write_input_tokens", output = "output_tokens"
    case reasoning = "reasoning_output_tokens", total = "total_tokens"
}

private typealias Fields = KeyedDecodingContainer<Field>

private extension Fields {
    func requiredID(_ key: Field) throws -> String {
        guard let value = try decodeIfPresent(String.self, forKey: key),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseFailure(category: .invalidIdentity)
        }
        return value
    }

    func optionalID(_ key: Field) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseFailure(category: .invalidIdentity)
        }
        return value
    }

    func positiveWindow() throws -> Int64? {
        guard let value = try decodeIfPresent(Int64.self, forKey: .window), value > 0 else {
            return nil
        }
        return value
    }

    func counterUsage(_ key: Field) throws -> TokenUsage? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        do {
            let fields = try nestedContainer(keyedBy: Field.self, forKey: key)
            return try TokenUsage(
                input: fields.decodeIfPresent(Int64.self, forKey: .input),
                cachedInput: fields.decodeIfPresent(Int64.self, forKey: .cachedInput),
                cacheWriteInput: fields.decodeIfPresent(Int64.self, forKey: .cacheWriteInput),
                output: fields.decodeIfPresent(Int64.self, forKey: .output),
                reasoning: fields.decodeIfPresent(Int64.self, forKey: .reasoning),
                total: fields.decodeIfPresent(Int64.self, forKey: .total)).validated()
        } catch {
            throw ParseFailure(category: .invalidCounters)
        }
    }

    func nativeRecord(timestamp: Date?, source: SourcePosition) throws -> UsageRecord {
        let key = try RequestKey(threadID: requiredID(.threadID), responseID: requiredID(.responseID))
        let taskID = try requiredID(.turnID)
        guard let usage = try counterUsage(.usage) else {
            throw ParseFailure(category: .malformedRecord)
        }
        return try UsageRecord(key: key, runtimeSessionID: optionalID(.sessionID),
            taskID: taskID, rootTaskID: optionalID(.rootTurnID), timestamp: timestamp,
            usage: usage, taskCumulative: counterUsage(.taskCumulative),
            threadCumulative: counterUsage(.threadCumulative), source: source)
    }

    func taskMetadata(timestamp: Date?, source: SourcePosition,
                      requiresID: Bool = false) throws -> TaskMetadata {
        try TaskMetadata(taskID: requiresID ? requiredID(.turnID) : optionalID(.turnID),
                         rootTaskID: optionalID(.rootTurnID),
                         modelContextWindow: positiveWindow(), timestamp: timestamp, source: source)
    }

    func toolEvent(timestamp: Date?, source: SourcePosition,
                   threadID: String? = nil, taskID: String? = nil,
                   completed: Bool = false) throws -> MetricEvent {
        let type = try decode(String.self, forKey: .type)
        switch type {
        case "function_call", "custom_tool_call":
            return try .toolCall(ToolCall(callID: requiredID(.callID), name: requiredID(.name),
                namespace: optionalID(.namespace), kind: type == "function_call" ? .function : .custom,
                itemID: optionalID(.id), threadID: threadID, taskID: taskID,
                isCompleted: completed, timestamp: timestamp, source: source))
        case "function_call_output", "custom_tool_call_output":
            return try .toolOutput(ToolOutput(callID: requiredID(.callID),
                kind: type == "function_call_output" ? .function : .custom,
                threadID: threadID, taskID: taskID, timestamp: timestamp, source: source))
        default:
            return .unknown
        }
    }
}

private struct Envelope: Decodable {
    let event: MetricEvent

    init(from decoder: any Decoder) throws {
        guard let source = decoder.userInfo[.sourcePosition] as? SourcePosition else {
            throw ParseFailure(category: .malformedRecord)
        }
        let envelope = try decoder.container(keyedBy: Field.self)
        let type = try envelope.decode(String.self, forKey: .type)
        guard ["session_meta", "turn_context", "token_usage_record", "event_msg",
               "response_item", "compacted"].contains(type) else {
            event = .unknown
            return
        }
        let timestamp = try Self.date(envelope.decodeIfPresent(String.self, forKey: .timestamp))
        let payload = try envelope.nestedContainer(keyedBy: Field.self, forKey: .payload)
        switch type {
        case "session_meta":
            event = try .header(SessionHeader(threadID: payload.requiredID(.id),
                runtimeSessionID: payload.optionalID(.sessionID),
                cliVersion: payload.decodeIfPresent(String.self, forKey: .cliVersion),
                parentThreadID: payload.optionalID(.parentThreadID), timestamp: timestamp, source: source))
        case "turn_context":
            event = try .configuredModel(ConfiguredModel(taskID: payload.requiredID(.turnID),
                rootTaskID: payload.optionalID(.rootTurnID),
                model: payload.optionalID(.model), timestamp: timestamp, source: source))
        case "token_usage_record":
            event = try .usageRecord(payload.nativeRecord(timestamp: timestamp, source: source))
        case "response_item":
            event = try payload.toolEvent(timestamp: timestamp, source: source)
        case "compacted":
            var latest: UsageRecord?
            if payload.contains(.latestRecord), try !payload.decodeNil(forKey: .latestRecord) {
                latest = try payload.nestedContainer(keyedBy: Field.self, forKey: .latestRecord)
                    .nativeRecord(timestamp: timestamp, source: source)
            }
            event = try .checkpoint(UsageCheckpoint(responseID: payload.optionalID(.compactionResponseID),
                latestUsageRecord: latest, timestamp: timestamp, source: source))
        case "event_msg":
            switch try payload.decode(String.self, forKey: .type) {
            case "task_started":
                event = try .taskStarted(payload.taskMetadata(timestamp: timestamp, source: source, requiresID: true))
            case "task_complete":
                event = try .taskFinished(payload.taskMetadata(timestamp: timestamp, source: source))
            case "turn_aborted":
                event = try .taskInterrupted(payload.taskMetadata(timestamp: timestamp, source: source))
            case "token_count":
                var info: Fields?
                if payload.contains(.info), try !payload.decodeNil(forKey: .info) {
                    info = try payload.nestedContainer(keyedBy: Field.self, forKey: .info)
                }
                event = try .usageSnapshot(UsageSnapshot(lastUsage: info?.counterUsage(.lastUsage),
                    cumulative: info?.counterUsage(.cumulative), modelContextWindow: info?.positiveWindow(),
                    timestamp: timestamp, source: source))
            case "item_completed":
                event = try payload.nestedContainer(keyedBy: Field.self, forKey: .item)
                    .toolEvent(timestamp: timestamp, source: source,
                               threadID: payload.optionalID(.threadID), taskID: payload.optionalID(.turnID),
                               completed: true)
            default:
                event = .unknown
            }
        default:
            event = .unknown
        }
    }

    private static func date(_ text: String?) throws -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else {
            throw ParseFailure(category: .malformedRecord)
        }
        return date
    }
}
