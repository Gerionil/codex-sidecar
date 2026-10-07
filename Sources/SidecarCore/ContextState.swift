import Foundation

public struct RequestFootprint: Equatable, Sendable {
    public let key: RequestKey
    public let total: Int64?
    public let timestamp: Date?
}

public struct ContextState: Equatable, Sendable {
    public internal(set) var configuredModel: ConfiguredModel?
    public internal(set) var window: Int64?
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
        var seen = Set<RequestKey>()
        var active = Set<String>()
        var latestUsage: TokenUsage?
        let trusted = Set(requests.map(\.key))
        for event in events {
            switch event {
            case .taskStarted(let task):
                if let id = task.taskID { active.insert(id) }
                if task.taskID != taskID {
                    state.window = nil
                    state.configuredModel = task.taskID.flatMap { models[$0] }
                    state.footprintIsHistorical = true
                }
                taskID = task.taskID
                state.window = task.modelContextWindow
            case .configuredModel(let model):
                let previous = models[model.taskID]
                models[model.taskID] = model
                if taskID != model.taskID || (previous != nil && previous?.model != model.model) {
                    state.window = nil
                    state.footprintIsHistorical = true
                }
                taskID = model.taskID
                state.configuredModel = model
            case .usageSnapshot(let snapshot):
                // Snapshot capacity is tied only to the unambiguous current task context.
                if active.count > 1 {
                    state.window = nil
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
                state.window = snapshot.modelContextWindow
            case .usageRecord(let record):
                guard trusted.contains(record.key), seen.insert(record.key).inserted else { continue }
                if record.taskID != taskID {
                    state.window = nil
                    state.configuredModel = models[record.taskID]
                }
                taskID = record.taskID
                latestUsage = record.usage
                state.lastRequestFootprint = RequestFootprint(key: record.key,
                    total: record.usage.total, timestamp: record.timestamp)
                state.footprintIsHistorical = false
            case .checkpoint:
                state.window = nil
                state.footprintIsHistorical = true
            case .taskInterrupted(let task):
                if let id = task.taskID { active.remove(id) } else { active.removeAll() }
                state.window = nil
                state.footprintIsHistorical = true
            case .taskFinished(let task):
                if let id = task.taskID { active.remove(id) } else { active.removeAll() }
            default: break
            }
        }
        return state
    }
}
