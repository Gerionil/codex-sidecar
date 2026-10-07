import Foundation

public enum CounterValidationError: Error, Sendable {
    case negative, subsetExceedsParent, inconsistentTotal, overflow
}

/// Missing fields stay unavailable. Cache and reasoning counters are subsets.
public struct TokenUsage: Equatable, Sendable {
    public let input: Int64?
    public let cachedInput: Int64?
    public let cacheWriteInput: Int64?
    public let output: Int64?
    public let reasoning: Int64?
    public let total: Int64?

    public init(input: Int64? = nil, cachedInput: Int64? = nil,
                cacheWriteInput: Int64? = nil, output: Int64? = nil,
                reasoning: Int64? = nil, total: Int64? = nil) {
        self.input = input
        self.cachedInput = cachedInput
        self.cacheWriteInput = cacheWriteInput
        self.output = output
        self.reasoning = reasoning
        self.total = total
    }

    @discardableResult
    public func validated() throws -> TokenUsage {
        for value in [input, cachedInput, cacheWriteInput, output, reasoning, total] {
            if let value, value < 0 { throw CounterValidationError.negative }
        }
        if let input, let cachedInput, cachedInput > input {
            throw CounterValidationError.subsetExceedsParent
        }
        if let output, let reasoning, reasoning > output {
            throw CounterValidationError.subsetExceedsParent
        }
        // Known subsets constrain absent parents without filling missing fields.
        let minimumInput = input ?? cachedInput ?? 0
        let minimumOutput = output ?? reasoning ?? 0
        let (minimumTotal, overflow) = minimumInput.addingReportingOverflow(minimumOutput)
        guard !overflow else { throw CounterValidationError.overflow }
        if let total {
            guard total >= minimumTotal else { throw CounterValidationError.inconsistentTotal }
            if input != nil, output != nil, total != minimumTotal {
                throw CounterValidationError.inconsistentTotal
            }
        }
        return self
    }

    /// A field is available in the sum only if both operands provide it.
    public func adding(_ other: TokenUsage) throws -> TokenUsage {
        try validated()
        try other.validated()
        func sum(_ a: Int64?, _ b: Int64?) throws -> Int64? {
            guard let a, let b else { return nil }
            let (value, overflow) = a.addingReportingOverflow(b)
            guard !overflow else { throw CounterValidationError.overflow }
            return value
        }
        return try TokenUsage(input: sum(input, other.input),
                              cachedInput: sum(cachedInput, other.cachedInput),
                              cacheWriteInput: sum(cacheWriteInput, other.cacheWriteInput),
                              output: sum(output, other.output),
                              reasoning: sum(reasoning, other.reasoning),
                              total: sum(total, other.total)).validated()
    }
}

public struct SourcePosition: Equatable, Sendable {
    /// Logical identifier supplied by the reader, never a private filesystem path.
    public let fileID: String
    public let byteOffset: Int64
    public init(fileID: String, byteOffset: Int64) {
        self.fileID = fileID
        self.byteOffset = byteOffset
    }
}

public struct RequestKey: Hashable, Sendable {
    public let threadID: String
    public let responseID: String
    public init(threadID: String, responseID: String) {
        self.threadID = threadID
        self.responseID = responseID
    }
}

public struct UsageRecord: Equatable, Sendable {
    public let key: RequestKey
    public let runtimeSessionID: String?
    public let taskID: String
    public let rootTaskID: String?
    public let timestamp: Date?
    public let usage: TokenUsage
    public let taskCumulative: TokenUsage?
    public let threadCumulative: TokenUsage?
    public let source: SourcePosition
}

public struct SessionHeader: Equatable, Sendable {
    public let threadID: String
    public let runtimeSessionID: String?
    public let cliVersion: String?
    public let parentThreadID: String?
    public let timestamp: Date?
    public let source: SourcePosition
}

public struct TaskMetadata: Equatable, Sendable {
    public let taskID: String?
    public let rootTaskID: String?
    public let modelContextWindow: Int64?
    public let timestamp: Date?
    public let source: SourcePosition
}

/// A configured model label, never attribution of an actual response model.
public struct ConfiguredModel: Equatable, Sendable {
    public let taskID: String
    public let rootTaskID: String?
    public let model: String?
    public let timestamp: Date?
    public let source: SourcePosition
}

public struct UsageSnapshot: Equatable, Sendable {
    public let lastUsage: TokenUsage?
    public let cumulative: TokenUsage?
    public let modelContextWindow: Int64?
    public let timestamp: Date?
    public let source: SourcePosition
}

public enum ToolKind: String, Equatable, Sendable { case function, custom }

public struct ToolCall: Equatable, Sendable {
    public let callID: String
    public let name: String
    public let namespace: String?
    public let kind: ToolKind
    public let itemID: String?
    public let threadID: String?
    public let taskID: String?
    public let isCompleted: Bool
    public let timestamp: Date?
    public let source: SourcePosition
}

public struct ToolOutput: Equatable, Sendable {
    public let callID: String
    public let kind: ToolKind
    public let threadID: String?
    public let taskID: String?
    public let timestamp: Date?
    public let source: SourcePosition
}

public struct UsageCheckpoint: Equatable, Sendable {
    public let responseID: String?
    public let latestUsageRecord: UsageRecord?
    public let timestamp: Date?
    public let source: SourcePosition
}

public enum MetricEvent: Equatable, Sendable {
    case header(SessionHeader)
    case taskStarted(TaskMetadata)
    case taskFinished(TaskMetadata)
    case taskInterrupted(TaskMetadata)
    case configuredModel(ConfiguredModel)
    case usageRecord(UsageRecord)
    case usageSnapshot(UsageSnapshot)
    case toolCall(ToolCall)
    case toolOutput(ToolOutput)
    case checkpoint(UsageCheckpoint)
    case unknown
}

public struct SanitizedDiagnostic: Equatable, Sendable {
    public enum Category: String, Sendable {
        case malformedRecord, invalidCounters, invalidIdentity, oversizedRecord
        case conflictingResponse, aggregateOverflow, missingTaskStart, ownershipAmbiguity, reconciliationBoundary, ambiguousTool
    }
    public let category: Category
    public let line: Int64?
    public let byteOffset: Int64?
    public let occurrenceCount: Int

    public init(category: Category, line: Int64? = nil, byteOffset: Int64? = nil,
                occurrenceCount: Int = 1) {
        self.category = category
        self.line = line
        self.byteOffset = byteOffset
        self.occurrenceCount = occurrenceCount
    }
}

public struct DecodeResult: Equatable, Sendable {
    public let event: MetricEvent?
    public let diagnostics: [SanitizedDiagnostic]
}

extension MetricEvent {
    var source: SourcePosition? {
        switch self {
        case .header(let value): value.source
        case .taskStarted(let value), .taskFinished(let value), .taskInterrupted(let value): value.source
        case .configuredModel(let value): value.source
        case .usageRecord(let value): value.source
        case .usageSnapshot(let value): value.source
        case .toolCall(let value): value.source
        case .toolOutput(let value): value.source
        case .checkpoint(let value): value.source
        case .unknown: nil
        }
    }
}

extension TokenUsage {
    static let zero = TokenUsage(input: 0, cachedInput: 0, cacheWriteInput: 0,
                                 output: 0, reasoning: 0, total: 0)

    /// Compare only reported fields, but never certify a missing observed counterpart.
    func matchesReported(_ reported: TokenUsage) -> Bool {
        zip(fields, reported.fields).allSatisfy { observed, reported in
            reported == nil || observed == reported
        }
    }

    var fields: [Int64?] { [input, cachedInput, cacheWriteInput, output, reasoning, total] }

    func subtracting(_ other: TokenUsage) throws -> TokenUsage {
        func difference(_ a: Int64?, _ b: Int64?) throws -> Int64? {
            guard let a, let b else { return nil }
            let (value, overflow) = a.subtractingReportingOverflow(b)
            guard !overflow, value >= 0 else { throw CounterValidationError.inconsistentTotal }
            return value
        }
        return try TokenUsage(input: difference(input, other.input),
                              cachedInput: difference(cachedInput, other.cachedInput),
                              cacheWriteInput: difference(cacheWriteInput, other.cacheWriteInput),
                              output: difference(output, other.output),
                              reasoning: difference(reasoning, other.reasoning),
                              total: difference(total, other.total)).validated()
    }
}
