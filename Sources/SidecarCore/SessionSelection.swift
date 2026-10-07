import Foundation

/// Recent filesystem activity is a suggestion only, never foreground identity.
public struct SessionSelection: Sendable {
    public private(set) var pinnedID: String?
    public private(set) var mostRecentSuggestion: SessionDescriptor?
    public private(set) var recentCandidates: [SessionDescriptor] = []
    public init() {}
    public mutating func pin(_ id: String?) { pinnedID = id }
    public mutating func update(_ sessions: [SessionDescriptor]) {
        let roots = sessions.filter { $0.parentThreadID == nil && $0.lastActivity != nil }
        let latest = roots.compactMap(\.lastActivity).max()
        recentCandidates = roots.filter { $0.lastActivity == latest }.sorted { $0.id < $1.id }
        mostRecentSuggestion = recentCandidates.count == 1 ? recentCandidates[0] : nil
    }
}
