import Foundation

public struct RequestFootprint: Equatable, Sendable {
    public let key: RequestKey
    public let total: Int64?
    public let timestamp: Date?
}

public struct ContextWindow: Equatable, Sendable {
    public let size: Int64
    public let taskID: String?
    public let configuredModel: ConfiguredModel?
    public let timestamp: Date?
    public let source: SourcePosition
}

public struct ContextState: Equatable, Sendable {
    public internal(set) var configuredModel: ConfiguredModel?
    public var window: Int64? { windowEvidence?.size }
    public internal(set) var windowEvidence: ContextWindow?
    public internal(set) var configuredModelIsHistorical = true
    public internal(set) var lastRequestFootprint: RequestFootprint?
    public internal(set) var footprintIsHistorical = true
    /// No validated source reports exact current occupancy.
    public var exactCurrentUsage: Int64? { nil }
    public var lastRequestRatio: Double? {
        guard !footprintIsHistorical, let total = lastRequestFootprint?.total,
              let window, window > 0 else { return nil }
        return Double(total) / Double(window)
    }
}

extension ContextState {
    static func reduce(_ events: [MetricEvent], requests: [ObservedRequest]) -> ContextState {
        var state = ContextState()
        var taskID: String?
        var models: [String: ConfiguredModel] = [:]
        var sourceModels: [String: [String: ConfiguredModel]] = [:]
        var seen = Set<RequestKey>()
        var active = Set<String>()
        var latestUsage: TokenUsage?
        let trusted = Set(requests.map(\.key))
        for event in events {
            switch event {
            case .taskStarted(let task):
                if let id = task.taskID { active.insert(id) }
                if task.taskID != taskID {
                    state.windowEvidence = nil
                    state.configuredModel = task.taskID.flatMap { models[$0] }
                    state.footprintIsHistorical = true
                    state.configuredModelIsHistorical = true
                }
                if state.window != task.modelContextWindow { state.footprintIsHistorical = true }
                taskID = task.taskID
                state.windowEvidence = task.modelContextWindow.map {
                    ContextWindow(size: $0, taskID: taskID, configuredModel: state.configuredModel,
                                  timestamp: task.timestamp, source: task.source)
                }
            case .configuredModel(let model):
                let previous = models[model.taskID]
                models[model.taskID] = model
                sourceModels[model.taskID, default: [:]][model.source.fileID] = model
                if taskID != model.taskID || (previous != nil && previous?.model != model.model) {
                    state.windowEvidence = nil
                    state.footprintIsHistorical = true
                }
                taskID = model.taskID
                state.configuredModel = model
                state.configuredModelIsHistorical = model.model == nil
                if let evidence = state.windowEvidence, evidence.taskID == model.taskID {
                    state.windowEvidence = ContextWindow(size: evidence.size, taskID: evidence.taskID,
                        configuredModel: model, timestamp: evidence.timestamp, source: evidence.source)
                }
            case .usageSnapshot(let snapshot):
                // Snapshot capacity is tied only to the unambiguous current task context.
                if active.count > 1 {
                    state.windowEvidence = nil
                    state.footprintIsHistorical = true
                    continue
                }
                if state.window != snapshot.modelContextWindow {
                    // Fresh native usage after an invalidation can acquire a
                    // matching advertised capacity without reviving an old footprint.
                    let freshMatching = state.window == nil && snapshot.modelContextWindow != nil
                        && latestUsage != nil && latestUsage == snapshot.lastUsage
                        && !state.footprintIsHistorical
                    if !freshMatching { state.footprintIsHistorical = true }
                }
                state.windowEvidence = snapshot.modelContextWindow.map {
                    ContextWindow(size: $0, taskID: taskID, configuredModel: state.configuredModel,
                                  timestamp: snapshot.timestamp, source: snapshot.source)
                }
            case .usageRecord(let record):
                guard trusted.contains(record.key), seen.insert(record.key).inserted else { continue }
                if record.taskID != taskID {
                    state.windowEvidence = nil
                    state.configuredModel = models[record.taskID]
                }
                taskID = record.taskID
                latestUsage = record.usage
                state.lastRequestFootprint = RequestFootprint(key: record.key,
                    total: record.usage.total, timestamp: record.timestamp)
                state.footprintIsHistorical = false
            case .checkpoint:
                state.windowEvidence = nil
                state.footprintIsHistorical = true
                state.configuredModelIsHistorical = true
            case .taskInterrupted(let task):
                if let id = task.taskID { active.remove(id) } else { active.removeAll() }
                state.windowEvidence = nil
                state.footprintIsHistorical = true
                state.configuredModelIsHistorical = true
            case .taskFinished(let task):
                if let id = task.taskID { active.remove(id) } else { active.removeAll() }
            default: break
            }
        }
        if let taskID, let contexts = sourceModels[taskID],
           Set(contexts.values.compactMap(\.model)).count > 1 {
            // Incompatible source copies cannot establish the current configured model.
            state.configuredModel = nil
            state.configuredModelIsHistorical = true
            state.windowEvidence = nil
            state.footprintIsHistorical = true
        }
        return state
    }
}
