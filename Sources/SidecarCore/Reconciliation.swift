import Foundation

public struct ReconciliationState: Equatable, Sendable {
    public enum Status: Sendable { case unavailable, reconciled, partialHistory, degraded, legacySnapshot }
    public internal(set) var status: Status = .unavailable
    public internal(set) var baseline: TokenUsage?
    public internal(set) var reportedCumulative: TokenUsage?
}

/// Native usage and source-reported cumulative values never share an accounting sum.
struct Reconciliation {
    static func reduce(_ events: [MetricEvent], records: [UsageRecord],
                       owningThreadID: String, degraded: Bool) -> ReconciliationState {
        var state = ReconciliationState()
        var invalid = degraded
        var sum = TokenUsage.zero
        var seen = Set<RequestKey>()
        var checkpointSeed: TokenUsage?
        var legacySeen = false
        var missingCumulative = false
        let trusted = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) })
        for event in events {
            switch event {
            case .usageSnapshot(let snapshot):
                if let cumulative = snapshot.cumulative {
                    if seen.isEmpty { legacySeen = true; state.reportedCumulative = cumulative }
                }
            case .checkpoint(let checkpoint):
                guard let record = checkpoint.latestUsageRecord,
                      record.key.threadID == owningThreadID,
                      let cumulative = record.threadCumulative else { continue }
                if seen.isEmpty {
                    checkpointSeed = cumulative
                    state.reportedCumulative = cumulative
                } else if let native = trusted[record.key], seen.contains(record.key) {
                    // A copied checkpoint corroborates its own response boundary,
                    // not the final sum reached in another source copy.
                    if native.usage != record.usage || native.threadCumulative != record.threadCumulative {
                        invalid = true
                    }
                } else if let baseline = state.baseline {
                    do {
                        if try !baseline.adding(sum).matchesReported(cumulative) { invalid = true }
                    } catch { invalid = true }
                }
            case .usageRecord(let record):
                guard trusted[record.key] != nil, seen.insert(record.key).inserted else { continue }
                do { sum = try sum.adding(record.usage) } catch { invalid = true }
                guard let cumulative = record.threadCumulative else {
                    missingCumulative = true
                    continue
                }
                state.reportedCumulative = cumulative
                if cumulative.total == nil { missingCumulative = true }
                if state.baseline == nil {
                    // The first native response is the only safe baseline boundary.
                    if seen.count != 1 { invalid = true }
                    do {
                        state.baseline = try cumulative.subtracting(record.usage)
                        if let checkpointSeed,
                           state.baseline?.matchesReported(checkpointSeed) != true { invalid = true }
                    } catch { invalid = true }
                } else if let baseline = state.baseline {
                    do {
                        if try !baseline.adding(sum).matchesReported(cumulative) { invalid = true }
                    } catch { invalid = true }
                }
            default: break
            }
        }
        if invalid { state.status = .degraded }
        else if records.isEmpty {
            state.status = state.reportedCumulative == nil ? .unavailable
                : (checkpointSeed == nil ? .legacySnapshot : .partialHistory)
        } else if let baseline = state.baseline, baseline.total != nil {
            let positive = baseline.fields.compactMap { $0 }.contains { $0 > 0 }
            state.status = positive || missingCumulative || legacySeen
                ? .partialHistory : .reconciled
        } else { state.status = .partialHistory }
        return state
    }
}
