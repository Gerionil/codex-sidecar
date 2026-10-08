import SwiftUI
import SidecarCore

struct CompanionView: View {
    @ObservedObject var store: SidecarStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ChatSelector(store: store)
                QuotaSection(store: store)
                ContextSection(store: store)
                UsageSection(store: store)
                requestList
            }.padding()
        }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refreshQuotas() } }.keyboardShortcut("r")
            SettingsLink()
        }
    }
    private var requestList: some View {
        GroupBox("Recent completed model requests") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Observed completed records only; stream order. At most 100 rows per page.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.page.rows.isEmpty { Text("Unavailable — No completed requests observed") }
                ForEach(store.page.rows, id: \.key) { request in
                    DisclosureGroup {
                        RequestDetail(request: request)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(PresentationText.number(request.usage.total)) tokens").monospacedDigit().textSelection(.enabled)
                            Text(PresentationText.time(request.timestamp)).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                HStack {
                    Button("Newer requests") { store.newerRequests() }.disabled(!store.page.hasNewer)
                    Spacer()
                    Button("Earlier requests") { store.earlierRequests() }.disabled(!store.page.hasEarlier)
                }
                if let session = store.session {
                    Divider()
                    Text("Task activity").font(.headline)
                    ForEach(Array(SessionPresentation(session).taskActivity.enumerated()), id: \.offset) { _, text in
                        Text(text).font(.caption).textSelection(.enabled)
                    }
                    if !session.unattributedTools.isEmpty {
                        Text("Unattributed task activity — no individual token cost").font(.subheadline)
                        ForEach(Array(session.unattributedTools.enumerated()), id: \.offset) { _, tool in ToolRow(tool: tool) }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ChatSelector: View {
    @ObservedObject var store: SidecarStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Selected chat", selection: Binding(get: { store.selectedID ?? "" }, set: { value in
                Task { await store.selectSession(id: value) }
            })) {
                Text("Choose a chat").tag("")
                if let id = store.selectedID, !store.sessions.contains(where: { $0.id == id }) {
                    Text("Pinned chat · Sources unavailable").tag(id)
                }
                ForEach(store.sessions, id: \.id) { Text(store.sessionLabels[$0.id] ?? "Unavailable").tag($0.id) }
            }
            .accessibilityLabel("Selected chat")
            Text("Manual selection · Pinned until changed").font(.caption).foregroundStyle(.secondary)
            if let descriptor = store.selectedDescriptor {
                Text(store.sessionLabels[descriptor.id] ?? "Unavailable").font(.caption).textSelection(.enabled)
                Text("Last activity: \(PresentationText.time(descriptor.lastActivity))").font(.caption).textSelection(.enabled)
                Text("Log profile: \(descriptor.cliVersion ?? "Unknown") · Internal version-sensitive format").font(.caption).foregroundStyle(.secondary)
            }
            Text(store.sessionStatus).font(.caption)
        }
    }
}
struct QuotaSection: View {
    @ObservedObject var store: SidecarStore
    var body: some View {
        let p = QuotaPresentation(store.quota, bucketID: store.selectedBucketID)
        GroupBox("Current account limits") {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.status).font(.caption).accessibilityLabel("Quota status: \(p.status)")
                if let snapshot = store.quota.lastGood {
                    Picker("Limit bucket", selection: Binding(get: { store.selectedBucketID ?? "" }, set: { store.selectBucket(id: $0.isEmpty ? nil : $0) })) {
                        Text("Choose a bucket").tag("")
                        ForEach(snapshot.buckets) { bucket in Text(bucket.name.map { "\($0) (\(bucket.id))" } ?? bucket.id).tag(bucket.id) }
                    }
                    if let bucket = snapshot.buckets.first(where: { $0.id == store.selectedBucketID }), let alias = bucket.normalModelSlug {
                        Text("Model alias metadata: \(alias)").font(.caption)
                    }
                    if !store.bucketSelectionStatus.isEmpty { Text(store.bucketSelectionStatus).font(.caption) }
                    if p.windows.isEmpty { Text(store.selectedBucketID == nil ? "Select a limit bucket" : "No windows returned for this bucket").font(.caption) }
                    ForEach(p.windows) { window in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(window.label)
                                Spacer(minLength: 8)
                                Text(window.remaining).monospacedDigit().textSelection(.enabled)
                            }
                            Text(window.reset).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Text("Received: \(p.received)").font(.caption).textSelection(.enabled)
                    if !snapshot.warnings.isEmpty { Text("Source warnings: \(snapshot.warnings.map(\.rawValue).joined(separator: ", "))").font(.caption) }
                }
                Text("Current account; independent of selected chat. Missing permissions do not confirm entitlement.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Offline mode", isOn: Binding(get: { store.settings.offline }, set: { enabled in Task { await store.setOffline(enabled) } }))
                Text(store.compatibility).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
struct ContextSection: View {
    @ObservedObject var store: SidecarStore
    var body: some View {
        let p = SessionPresentation(store.session)
        GroupBox("Context") {
            VStack(alignment: .leading, spacing: 8) {
                MetricRow(title: "Current context usage", value: p.currentContext)
                MetricRow(title: "Model context window (source)", value: p.window)
                MetricRow(title: "Last request footprint", value: p.footprint)
                MetricRow(title: "Configured model", value: p.configuredModel)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
struct UsageSection: View {
    @ObservedObject var store: SidecarStore
    var body: some View {
        let p = SessionPresentation(store.session)
        GroupBox("Observed session tokens") {
            VStack(alignment: .leading, spacing: 8) {
                MetricRow(title: "Completed response sum", value: p.observedTotal)
                Text(p.reconciliation).font(.caption)
                Text("Selected chat only; observed files may omit earlier or interrupted usage.").font(.caption).foregroundStyle(.secondary)
                MetricRow(title: "Cache hit rate (same observed records)", value: p.cacheRate)
                DisclosureGroup("Breakdown and reported cumulative") {
                    UsageBreakdown(usage: store.session?.totals)
                    MetricRow(title: "Reported cumulative (separate source value)", value: p.reportedCumulative)
                }
                if let count = store.session?.diagnostics.count, count > 0 {
                    Text("\(count) sanitized source diagnostics; coverage may be incomplete").font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
struct MetricRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).monospacedDigit().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(title): \(value)")
        }
    }
}
struct UsageBreakdown: View {
    let usage: TokenUsage?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MetricRow(title: "Input", value: PresentationText.number(usage?.input))
            MetricRow(title: "Cached input — included in input", value: PresentationText.number(usage?.cachedInput))
            MetricRow(title: "Cache write input — included in input", value: PresentationText.number(usage?.cacheWriteInput))
            MetricRow(title: "Output", value: PresentationText.number(usage?.output))
            MetricRow(title: "Reasoning output — included in output", value: PresentationText.number(usage?.reasoning))
        }
    }
}
struct RequestDetail: View {
    let request: ObservedRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageBreakdown(usage: request.usage)
            MetricRow(title: "Configured model (task provenance)", value: request.configuredModel?.model ?? "Unavailable")
            Text("Tool association confidence: \(request.tools.contains(where: \.isAmbiguous) ? "Ambiguous" : "Stream-order association only")").font(.caption)
            Text("\(request.tools.count) associated tool calls; no individual token costs").font(.caption)
            ForEach(Array(request.tools.enumerated()), id: \.offset) { _, tool in ToolRow(tool: tool) }
        }
    }
}
struct ToolRow: View {
    let tool: AssociatedTool
    var body: some View {
        Text("\(tool.name ?? "Unknown tool") · \(tool.callCompleted ? "Call completed" : "Completion unknown") · \(tool.outputReceived ? "Output observed" : "Output not observed") · \(tool.isAmbiguous ? "Ambiguous association" : "Stream order")")
            .font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
}
