import Foundation

/// Display values preserve missing counters and all scope distinctions.
public enum PresentationText {
    public static func number(_ value: Int64?) -> String { value.map { $0.formatted() } ?? "Unavailable" }
    public static func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...2))) + "%" } ?? "Unavailable"
    }
    public static func time(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium; formatter.timeStyle = .medium
        return formatter.string(from: date) + " " + (TimeZone.current.abbreviation(for: date) ?? TimeZone.current.identifier)
    }
    public static func descriptor(_ s: SessionDescriptor) -> String {
        let provenance = s.provenanceAmbiguous ? "Ambiguous provenance" : (s.parentThreadID == nil ? "Root" : "Child")
        return "\(s.projectName ?? "Unknown project") · \(s.id.prefix(8)) · \(provenance) · \(time(s.lastActivity))"
    }
    public static func failure(_ f: QuotaFailure) -> String {
        switch f {
        case .missingExecutable: "Codex executable missing"
        case .unsupportedProtocol: "Unsupported protocol or unverified executable"
        case .authenticationAbsent: "Authentication unavailable"
        case .apiKeyOnly: "Account limits unavailable for API key authentication"
        case .processExited: "Owned quota process exited"
        case .timeout: "Quota read timed out"
        case .malformedReply: "Malformed quota reply"
        case .requestFailed: "Quota request failed"
        case .offline: "Offline mode"
        case .stopped: "Stopped"
        case .cancelled: "Cancelled"
        }
    }
}
public struct SessionPresentation {
    public let observedTotal: String
    public let cacheRate: String
    public let configuredModel: String
    public let window: String
    public let currentContext = "Unavailable — exact current usage has no validated source"
    public let footprint: String
    public let reconciliation: String
    public let reportedCumulative: String
    public let taskActivity: [String]
    public init(_ session: DerivedSession?) {
        observedTotal = PresentationText.number(session?.totals.total)
        cacheRate = PresentationText.percent(session?.cacheHitPercent)
        let context = session?.context
        configuredModel = (context?.configuredModel?.model ?? "Unavailable")
            + (context?.configuredModelIsHistorical == true ? " (historical task configuration)" : " (task configuration)")
        window = PresentationText.number(context?.window)
        if let f = context?.lastRequestFootprint {
            footprint = "\(PresentationText.number(f.total)) · \(PresentationText.time(f.timestamp)) · "
                + (context?.footprintIsHistorical == true ? "Historical / stale" : "Last completed request")
        } else { footprint = "Unavailable" }
        switch session?.reconciliation.status {
        case .reconciled: reconciliation = "Reconciled observed usage"
        case .partialHistory: reconciliation = "Partial history"
        case .degraded: reconciliation = "Degraded reconciliation — partial history"
        case .legacySnapshot: reconciliation = "Reported snapshot usage — unverified lifetime scope"
        default: reconciliation = "Reconciliation unavailable"
        }
        reportedCumulative = PresentationText.number(session?.reconciliation.reportedCumulative?.total)
        taskActivity = session?.tasks.map { task in
            let status: String
            switch task.status { case .active: status = "Active"; case .completed: status = "Completed"
            case .interrupted: status = "Interrupted"; case .unknown: status = "Unknown lifecycle" }
            return "\(task.taskID) · \(status) · " + (task.usageReported ? "\(task.requestKeys.count) completed model requests" : "Usage not reported")
                + (task.hasStart ? "" : " · Start not observed")
        } ?? []
    }
}
public struct QuotaPresentation {
    public struct Window: Identifiable {
        public let id: String
        public let label: String
        public let remaining: String
        public let reset: String
    }
    public let status: String
    public let received: String
    public let windows: [Window]
    public init(_ state: QuotaState, bucketID: String?) {
        switch state {
        case .loading: status = "Loading"
        case .available: status = "Available · Codex app-server"
        case .unavailable(let reason): status = "Unavailable — \(PresentationText.failure(reason))"
        case .stale(_, let reason): status = "Stale — \(reason == .resetPassed ? "Reset passed; awaiting refresh" : reason.rawValue)"
        case .error(let reason, let last): status = "Error — \(PresentationText.failure(reason))" + (last == nil ? "" : " · Retained values are stale")
        }
        received = PresentationText.time(state.lastGood?.receivedAt)
        windows = state.lastGood?.buckets.first { $0.id == bucketID }?.windows.map {
            Window(id: $0.id, label: $0.label,
                   remaining: $0.remainingPercent.map { PresentationText.percent($0) + " remaining" } ?? "Unavailable",
                   reset: "Reset: \(PresentationText.time($0.resetAt))")
        } ?? []
    }
}
public struct RequestPage {
    public let rows: [ObservedRequest]
    public let hasEarlier: Bool
    public let hasNewer: Bool
    public init(session: DerivedSession?, page: Int) {
        let requests = session?.requests ?? []
        let end = max(0, requests.count - max(0, page) * 100)
        let start = max(0, end - 100)
        rows = Array(requests[start..<end].reversed())
        hasEarlier = start > 0; hasNewer = page > 0
    }
}
