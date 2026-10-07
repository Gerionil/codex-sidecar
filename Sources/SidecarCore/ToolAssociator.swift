import Foundation

public struct AssociatedTool: Equatable, Sendable {
    public let callID: String
    public let name: String?
    public let kind: ToolKind
    public let taskID: String?
    public let callCompleted: Bool
    public let outputReceived: Bool
    /// Stream order establishes an association, never an individual token cost.
    public let requestKey: RequestKey?
    public let isAmbiguous: Bool
}

/// A call belongs to the next native boundary in the same single-task segment.
/// Repeated copies must agree on that boundary; output alone is never a request.
struct ToolAssociator {
    private struct Entry {
        var name: String?
        var kind: ToolKind
        var taskID: String?
        var completed = false
        var output = false
        var candidates = Set<RequestKey>()
        var ambiguous = false
    }
    private struct Stream {
        var active = Set<String>()
        var pending = Set<String>()
        var seenCalls = Set<String>()
    }

    static func reduce(_ events: [MetricEvent], records: [UsageRecord],
                       owningThreadID: String) -> [AssociatedTool] {
        var streams: [String: Stream] = [:]
        var entries: [String: Entry] = [:]
        var order: [String] = []
        let trusted = Set(records.map(\.key))
        for event in events {
            guard let source = event.source else { continue }
            var stream = streams[source.fileID] ?? Stream()
            switch event {
            case .taskStarted(let task):
                if let id = task.taskID { stream.active.insert(id) }
            case .taskFinished(let task), .taskInterrupted(let task):
                for id in stream.pending { entries[id]?.ambiguous = true }
                stream.pending.removeAll()
                if let id = task.taskID { stream.active.remove(id) }
                else { stream.active.removeAll() }
            case .checkpoint:
                for id in stream.pending { entries[id]?.ambiguous = true }
                stream.pending.removeAll()
            case .toolCall(let call):
                guard call.threadID == nil || call.threadID == owningThreadID else { continue }
                let inferredTask = stream.active.count == 1 ? stream.active.first : nil
                let task = call.taskID ?? inferredTask
                let name = call.namespace.map { "\($0).\(call.name)" } ?? call.name
                if var entry = entries[call.callID] {
                    if entry.name != name || entry.kind != call.kind || entry.taskID != task {
                        entry.ambiguous = true
                    }
                    entry.completed = entry.completed || call.isCompleted
                    entries[call.callID] = entry
                } else {
                    order.append(call.callID)
                    entries[call.callID] = Entry(name: name, kind: call.kind, taskID: task,
                                               completed: call.isCompleted)
                }
                if stream.seenCalls.insert(call.callID).inserted {
                    stream.pending.insert(call.callID)
                    if stream.active.count != 1 || task != inferredTask { entries[call.callID]?.ambiguous = true }
                }
            case .toolOutput(let output):
                guard output.threadID == nil || output.threadID == owningThreadID else { continue }
                if var entry = entries[output.callID] {
                    if entry.kind != output.kind || (output.taskID != nil && entry.taskID != output.taskID) {
                        entry.ambiguous = true
                    }
                    entry.output = true
                    entries[output.callID] = entry
                } else {
                    order.append(output.callID)
                    entries[output.callID] = Entry(kind: output.kind, taskID: output.taskID,
                                                   output: true, ambiguous: true)
                }
            case .usageRecord(let record):
                for id in stream.pending {
                    if trusted.contains(record.key), stream.active.count == 1,
                       stream.active.contains(record.taskID), entries[id]?.taskID == record.taskID {
                        entries[id]?.candidates.insert(record.key)
                    } else { entries[id]?.ambiguous = true }
                }
                stream.pending.removeAll()
            default: break
            }
            streams[source.fileID] = stream
        }
        for stream in streams.values {
            for id in stream.pending { entries[id]?.ambiguous = true }
        }
        return order.compactMap { id in
            guard let entry = entries[id] else { return nil }
            let ambiguous = entry.ambiguous || entry.candidates.count != 1
            return AssociatedTool(callID: id, name: entry.name, kind: entry.kind, taskID: entry.taskID,
                callCompleted: entry.completed, outputReceived: entry.output,
                requestKey: ambiguous ? nil : entry.candidates.first, isAmbiguous: ambiguous)
        }
    }
}
