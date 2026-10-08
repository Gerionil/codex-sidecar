import Foundation

public struct ObservedRequest: Equatable, Sendable {
    public let key: RequestKey
    public let usage: TokenUsage
    public let taskID: String
    public let rootTaskID: String?
    public let runtimeSessionID: String?
    public let timestamp: Date?
    public let source: SourcePosition
    public let configuredModel: ConfiguredModel?
    public let tools: [AssociatedTool]
}

public struct DerivedTask: Equatable, Sendable {
    public enum Status: Sendable { case active, completed, interrupted, unknown }
    public let taskID: String
    public let hasStart: Bool
    public let status: Status
    public let requestKeys: [RequestKey]
    public var usageReported: Bool { !requestKeys.isEmpty }
}

public struct DerivedSession: Equatable, Sendable {
    /// Selected owner carried to consumers, including empty / unavailable snapshots.
    public internal(set) var owningThreadID: String? = nil
    public let requests: [ObservedRequest]
    public let tasks: [DerivedTask]
    public let totals: TokenUsage
    public let cacheHitPercent: Double?
    public internal(set) var reconciliation: ReconciliationState
    public let context: ContextState
    public let unattributedTools: [AssociatedTool]
    public let quarantinedKeys: [RequestKey]
    public internal(set) var diagnostics: [SanitizedDiagnostic]
    public internal(set) var sourceAvailability: SourceAvailability = .available
}

public struct SessionReducer {
    public static func reduce(_ events: [MetricEvent], owningThreadID: String) -> DerivedSession {
        var owners: [String: String] = [:]
        var filtered: [MetricEvent] = []
        var positions: [String: [Int64: [MetricEvent]]] = [:]
        var ownershipAmbiguous = false
        for event in events {
            guard let source = event.source else { continue }
            if case .header(let header) = event {
                if owners[source.fileID] == nil { owners[source.fileID] = header.threadID }
                continue // Inherited headers never change file ownership.
            }
            guard owners[source.fileID] == owningThreadID else {
                if case .usageRecord(let record) = event, record.key.threadID == owningThreadID {
                    ownershipAmbiguous = true
                }
                continue
            }
            let prior = positions[source.fileID]?[source.byteOffset] ?? []
            if prior.contains(event) { continue }
            positions[source.fileID, default: [:]][source.byteOffset, default: []].append(event)
            filtered.append(event)
        }

        // Exact copies and older prefixes have no additional evidence. Remove
        // them before lifecycle/context replay so they cannot reopen old tasks.
        let fileOrder = filtered.compactMap { $0.source?.fileID }.reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        let streams = Dictionary(grouping: filtered, by: { $0.source!.fileID })
        let signatures = streams.mapValues { $0.map(\.copySignature) }
        var redundant = Set<String>()
        for (index, fileID) in fileOrder.enumerated() {
            guard let stream = signatures[fileID] else { continue }
            for (otherIndex, otherID) in fileOrder.enumerated() where otherID != fileID {
                guard let other = signatures[otherID], other.count >= stream.count,
                      (other.count > stream.count || otherIndex < index),
                      Array(other.prefix(stream.count)) == stream else { continue }
                redundant.insert(fileID)
                break
            }
        }
        filtered.removeAll { redundant.contains($0.source!.fileID) }

        var ledger: [RequestKey: UsageRecord] = [:]
        var order: [RequestKey] = []
        var quarantine = Set<RequestKey>()
        var quarantinedKeys: [RequestKey] = []
        var diagnostics: [SanitizedDiagnostic] = []
        if ownershipAmbiguous { diagnostics.append(SanitizedDiagnostic(category: .ownershipAmbiguity)) }
        var models: [String: ConfiguredModel] = [:]
        var requestModels: [RequestKey: ConfiguredModel] = [:]
        var taskOrder: [String] = []
        var starts = Set<String>()
        var statuses: [String: DerivedTask.Status] = [:]
        var activeTasks: [String: Set<String>] = [:]
        var terminalSources: [String: String] = [:]
        var conflictingModels = Set<RequestKey>()
        func ensureTask(_ id: String) {
            if !taskOrder.contains(id) { taskOrder.append(id) }
        }
        for event in filtered {
            switch event {
            case .taskStarted(let task):
                if let id = task.taskID {
                    ensureTask(id); starts.insert(id)
                    if terminalSources[id] == nil || terminalSources[id] == task.source.fileID {
                        statuses[id] = .active
                    }
                    activeTasks[task.source.fileID, default: []].insert(id)
                }
            case .taskFinished(let task):
                let active = activeTasks[task.source.fileID] ?? []
                if let id = task.taskID ?? (active.count == 1 ? active.first : nil) {
                    ensureTask(id); statuses[id] = .completed
                    terminalSources[id] = task.source.fileID
                    activeTasks[task.source.fileID]?.remove(id)
                }
            case .taskInterrupted(let task):
                let active = activeTasks[task.source.fileID] ?? []
                if let id = task.taskID ?? (active.count == 1 ? active.first : nil) {
                    ensureTask(id); statuses[id] = .interrupted
                    terminalSources[id] = task.source.fileID
                    activeTasks[task.source.fileID]?.remove(id)
                }
            case .configuredModel(let model): models[model.taskID] = model
            case .usageRecord(let record):
                guard record.key.threadID == owningThreadID else { continue }
                ensureTask(record.taskID)
                guard !quarantine.contains(record.key) else { continue }
                let valid = !record.key.responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !record.taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (try? record.usage.validated()) != nil
                if let previous = ledger[record.key] {
                    if let first = requestModels[record.key]?.model,
                       let copy = models[record.taskID]?.model, first != copy {
                        conflictingModels.insert(record.key)
                    }
                    if !valid || !sameResponse(previous, record) {
                        ledger.removeValue(forKey: record.key)
                        quarantine.insert(record.key)
                        quarantinedKeys.append(record.key)
                        diagnostics.append(SanitizedDiagnostic(category: .conflictingResponse,
                                                               byteOffset: record.source.byteOffset))
                    }
                } else if valid {
                    if activeTasks[record.source.fileID]?.contains(record.taskID) == true,
                       let terminalSource = terminalSources[record.taskID], terminalSource != record.source.fileID {
                        statuses[record.taskID] = .active
                        terminalSources.removeValue(forKey: record.taskID)
                    }
                    ledger[record.key] = record
                    order.append(record.key)
                    requestModels[record.key] = models[record.taskID]
                } else {
                    quarantine.insert(record.key)
                    quarantinedKeys.append(record.key)
                    diagnostics.append(SanitizedDiagnostic(category: .invalidCounters,
                                                           byteOffset: record.source.byteOffset))
                }
            default: break
            }
        }
        let records = order.compactMap { ledger[$0] }
        var totals = TokenUsage.zero
        var overflow = false
        for record in records {
            do { totals = try totals.adding(record.usage) } catch { overflow = true }
        }
        if records.isEmpty || overflow { totals = TokenUsage() }
        if overflow { diagnostics.append(SanitizedDiagnostic(category: .aggregateOverflow)) }
        let tools = ToolAssociator.reduce(filtered, records: records, owningThreadID: owningThreadID)
        let requests = records.map { record in
            ObservedRequest(key: record.key, usage: record.usage, taskID: record.taskID,
                rootTaskID: record.rootTaskID, runtimeSessionID: record.runtimeSessionID,
                timestamp: record.timestamp, source: record.source, configuredModel: conflictingModels.contains(record.key) ? nil : requestModels[record.key],
                tools: tools.filter { $0.requestKey == record.key })
        }
        let tasks = taskOrder.map { id in
            if !starts.contains(id) { diagnostics.append(SanitizedDiagnostic(category: .missingTaskStart)) }
            return DerivedTask(taskID: id, hasStart: starts.contains(id), status: statuses[id] ?? .unknown,
                               requestKeys: records.filter { $0.taskID == id }.map(\.key))
        }
        let reconciliation = Reconciliation.reduce(filtered, records: records, owningThreadID: owningThreadID,
            degraded: ownershipAmbiguous || !quarantine.isEmpty || overflow)
        if reconciliation.status == .degraded {
            diagnostics.append(SanitizedDiagnostic(category: .reconciliationBoundary))
        }
        if tools.contains(where: \.isAmbiguous) { diagnostics.append(SanitizedDiagnostic(category: .ambiguousTool)) }
        let cacheRate: Double?
        if let input = totals.input, input > 0, let cached = totals.cachedInput {
            cacheRate = 100 * Double(cached) / Double(input)
        } else { cacheRate = nil }
        return DerivedSession(owningThreadID: owningThreadID, requests: requests, tasks: tasks, totals: totals, cacheHitPercent: cacheRate,
            reconciliation: reconciliation, context: ContextState.reduce(filtered, requests: requests),
            unattributedTools: tools.filter { $0.requestKey == nil }, quarantinedKeys: quarantinedKeys,
            diagnostics: diagnostics)
    }

    private static func sameResponse(_ lhs: UsageRecord, _ rhs: UsageRecord) -> Bool {
        lhs.usage == rhs.usage && lhs.taskID == rhs.taskID && lhs.rootTaskID == rhs.rootTaskID
            && lhs.taskCumulative == rhs.taskCumulative && lhs.threadCumulative == rhs.threadCumulative
    }
}
