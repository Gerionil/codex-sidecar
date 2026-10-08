import Foundation
import CoreFoundation

/// Stable categories only: never carries server error text or account identity.
public enum QuotaFailure: String, Error, Sendable, Equatable {
    case missingExecutable, unsupportedProtocol, authenticationAbsent, apiKeyOnly
    case processExited, timeout, malformedReply, requestFailed, offline, stopped, cancelled
}
public enum QuotaWarning: String, Sendable, Equatable {
    case malformedPercentage, percentageOutOfRange, malformedDuration, malformedReset, malformedWindow, malformedMetadata
}
public struct QuotaWindow: Sendable, Equatable, Identifiable {
    public enum Slot: String, Sendable { case primary, secondary }
    public let sourceSlot: Slot
    public var id: String { sourceSlot.rawValue }
    public let usedPercent: Double?
    public var remainingPercent: Double? { usedPercent.map { min(100, max(0, 100 - $0)) } }
    public let durationMinutes: Int64?
    public let resetAt: Date?
    public let label: String
}
public struct QuotaBucket: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    /// Alias metadata only; never actual-model attribution.
    public let normalModelSlug: String?
    public let spendControlReached: Bool?
    public let windows: [QuotaWindow]
}
public struct QuotaSnapshot: Sendable, Equatable {
    public let buckets: [QuotaBucket]
    public let ordinaryUsageAllowed: Bool?
    public let receivedAt: Date
    public let accountGeneration: UInt64
    public let warnings: [QuotaWarning]
    public var defaultBucketID: String? { buckets.contains { $0.id == "codex" } ? "codex" : nil }
    func stamped(generation: UInt64) -> Self {
        .init(buckets: buckets, ordinaryUsageAllowed: ordinaryUsageAllowed, receivedAt: receivedAt,
              accountGeneration: generation, warnings: warnings)
    }
}
public enum QuotaStaleReason: String, Sendable { case age, wake, resetPassed }
public enum QuotaState: Sendable, Equatable {
    case loading
    case available(QuotaSnapshot)
    case unavailable(QuotaFailure)
    case stale(QuotaSnapshot, QuotaStaleReason)
    case error(QuotaFailure, QuotaSnapshot?)
    public var lastGood: QuotaSnapshot? {
        switch self {
        case .available(let s), .stale(let s, _): s
        case .error(_, let s): s
        default: nil
        }
    }
}

public struct QuotaDecoder {
    public static func decodeRead(_ bytes: Data, receivedAt: Date) throws -> QuotaSnapshot {
        let object = try dictionary(bytes)
        var warnings: [QuotaWarning] = []
        let map: [String: Any]
        if let returned = object["rateLimitsByLimitId"], !(returned is NSNull) {
            guard let value = returned as? [String: Any] else { throw QuotaFailure.malformedReply }
            map = value
        } else {
            guard let legacy = object["rateLimits"] as? [String: Any] else { throw QuotaFailure.malformedReply }
            map = [legacy["limitId"] as? String ?? "legacy": legacy]
        }
        let buckets = try map.keys.sorted().map { id -> QuotaBucket in
            guard let bucket = map[id] as? [String: Any] else { throw QuotaFailure.malformedReply }
            var windows: [QuotaWindow] = []
            for slot in [QuotaWindow.Slot.primary, .secondary] {
                guard let raw = bucket[slot.rawValue], !(raw is NSNull) else { continue }
                guard let w = raw as? [String: Any] else { warnings.append(.malformedWindow); continue }
                let used = number(w["usedPercent"])
                if let used { if used < 0 || used > 100 { warnings.append(.percentageOutOfRange) } }
                else if nonnull(w["usedPercent"]) { warnings.append(.malformedPercentage) }
                let duration = integer(w["windowDurationMins"]).flatMap { $0 > 0 ? $0 : nil }
                if duration == nil, nonnull(w["windowDurationMins"]) { warnings.append(.malformedDuration) }
                // Date's useful civil range, rather than enormous unrenderable integer epochs.
                let reset = integer(w["resetsAt"]).flatMap { n -> Date? in
                    guard n >= -62135596800, n <= 253402300799 else { return nil }
                    return Date(timeIntervalSince1970: Double(n))
                }
                if reset == nil, nonnull(w["resetsAt"]) { warnings.append(.malformedReset) }
                let label: String
                switch duration { case 300: label = "5h"; case 10080: label = "Weekly"
                case .some(let n): label = "\(n) minutes"; case nil: label = "Unknown window" }
                windows.append(.init(sourceSlot: slot, usedPercent: used, durationMinutes: duration, resetAt: reset, label: label))
            }
            if windows.count == 2, let duration = windows[0].durationMinutes, duration == windows[1].durationMinutes {
                windows = windows.map { .init(sourceSlot: $0.sourceSlot, usedPercent: $0.usedPercent,
                    durationMinutes: $0.durationMinutes, resetAt: $0.resetAt, label: "\($0.label) (\($0.sourceSlot.rawValue))") }
            }
            return .init(id: id, name: bucket["limitName"] as? String, normalModelSlug: bucket["normalModelSlug"] as? String,
                         spendControlReached: boolean(bucket["spendControlReached"]), windows: windows)
        }
        return .init(buckets: buckets, ordinaryUsageAllowed: boolean(object["ordinaryUsageAllowed"]),
                     receivedAt: receivedAt, accountGeneration: 0, warnings: Array(Set(warnings.map(\.rawValue))).sorted().compactMap(QuotaWarning.init))
    }
    static func dictionary(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1024 * 1024,
              let value = try? JSONSerialization.jsonObject(with: data), let result = value as? [String: Any] else {
            throw QuotaFailure.malformedReply
        }
        return result
    }
    private static func nonnull(_ value: Any?) -> Bool { value != nil && !(value is NSNull) }
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    static func integer(_ value: Any?) -> Int64? {
        guard let n = number(value), n.rounded(.towardZero) == n, n >= Double(Int64.min), n < Double(Int64.max) else { return nil }
        return Int64(n)
    }
    static func boolean(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }
}
