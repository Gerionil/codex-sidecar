import SwiftUI
import SidecarCore

struct CompanionView: View {
    @ObservedObject var store: SidecarStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ChatSelector(store: store)
                Divider()
                QuotaSection(store: store)
                Divider()
                UsageSection(store: store)
                Divider()
                ContextSection(store: store)
                Divider()
                requestList
            }.padding(20)
        }
        .modifier(SidecarSurface())
        .toolbar { SidecarActions(store: store) }
    }
    private var requestList: some View {
        SidecarSection(title: "Recent completed requests") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Completed records only · Newest first")
                    .font(.caption).foregroundStyle(.secondary)
                if store.page.rows.isEmpty { Text("Unavailable — No completed requests observed") }
                ForEach(store.page.rows, id: \.key) { request in
                    DisclosureGroup {
                        RequestDetail(request: request)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(PresentationText.number(request.usage.total)) tokens").monospacedDigit().textSelection(.enabled)
                            Text(PresentationText.compactTime(request.timestamp)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                .help(PresentationText.time(request.timestamp))
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
                    TaskActivityView(session: session).id(store.selectedID)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ChatSelector: View {
    @ObservedObject var store: SidecarStore
    @State private var showingChats = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected chat").font(.caption).foregroundStyle(.secondary)
            Button { showingChats = true } label: {
                HStack {
                    Text(store.selectedDescriptor?.title ?? store.selectedDescriptor.map { String($0.id.prefix(8)) }
                         ?? (store.selectedID == nil ? "Choose a chat" : "Pinned chat unavailable"))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showingChats, arrowEdge: .bottom) {
                ChatBrowser(store: store) { showingChats = false }
                    .preferredColorScheme(store.settings.appearance.colorScheme)
            }
            .accessibilityLabel("Selected chat")
            .accessibilityValue(store.selectedID.flatMap { store.sessionLabels[$0] } ?? "No chat selected")
            if let descriptor = store.selectedDescriptor {
                Text("\(descriptor.projectName ?? "Unknown project") · \(PresentationText.compactTime(descriptor.lastActivity))")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .help(store.sessionLabels[descriptor.id] ?? "Unavailable")
                Label("Manually selected", systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Chat details") {
                    Text(store.sessionLabels[descriptor.id] ?? "Unavailable").textSelection(.enabled)
                    Text("Last activity: \(PresentationText.time(descriptor.lastActivity))").textSelection(.enabled)
                    Text("Log profile: \(descriptor.cliVersion ?? "Unknown") · Internal version-sensitive format")
                }.font(.caption)
            }
            if store.sessionStatus != "Available · Local rollout files" {
                Text(store.sessionStatus).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct QuotaSection: View {
    @ObservedObject var store: SidecarStore
    var body: some View {
        let p = QuotaPresentation(store.quota, bucketID: store.selectedBucketID)
        SidecarSection(title: "Account limits") {
            if let snapshot = store.quota.lastGood {
                Picker("Limit bucket", selection: Binding(get: { store.selectedBucketID ?? "" }, set: { store.selectBucket(id: $0.isEmpty ? nil : $0) })) {
                    Text("Choose a bucket").tag("")
                    ForEach(snapshot.buckets) { bucket in Text(PresentationText.bucketDescriptor(bucket, peers: snapshot.buckets)).tag(bucket.id) }
                }.accessibilityLabel("Limit bucket")
                if !store.bucketSelectionStatus.isEmpty { Text(store.bucketSelectionStatus).font(.caption) }
                if p.windows.isEmpty { Text(store.selectedBucketID == nil ? "Select a limit bucket" : "No windows returned for this bucket").font(.caption) }
                ForEach(p.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(window.label)
                            Spacer(minLength: 8)
                            Text(window.remaining).monospacedDigit().textSelection(.enabled)
                        }.accessibilityElement(children: .combine)
                        if let raw = snapshot.buckets.first(where: { $0.id == store.selectedBucketID })?.windows.first(where: { $0.id == window.id }),
                           let remaining = raw.remainingPercent {
                            ProgressView(value: remaining, total: 100)
                                .accessibilityLabel("\(window.label) remaining quota")
                                .accessibilityValue(window.remaining)
                        }
                        Text(window.reset).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Text("Received: \(p.received)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if !snapshot.warnings.isEmpty {
                    Text("Source warnings: \(snapshot.warnings.map(\.rawValue).joined(separator: ", "))").font(.caption)
                }
            }
            Text(p.status).font(.caption).accessibilityLabel("Quota status: \(p.status)")
            Text("Account-wide · Independent of selected chat").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Quota source details") {
                Text("Missing permissions do not confirm entitlement.")
                if let bucket = store.quota.lastGood?.buckets.first(where: { $0.id == store.selectedBucketID }) {
                    Text("Bucket: \(bucket.id)")
                    if let alias = bucket.normalModelSlug { Text("Model alias metadata: \(alias)") }
                }
                Text(store.compatibility)
            }.font(.caption)
        }
    }
}

struct ContextSection: View {
    @ObservedObject var store: SidecarStore
    var compact = false
    var body: some View {
        let p = SessionPresentation(store.session)
        SidecarSection(title: compact ? "Context" : "Context and model") {
            Label("Current context usage unavailable", systemImage: "info.circle")
                .font(.caption).accessibilityLabel(p.currentContext)
            MetricRow(title: "Advertised window", value: p.window)
            MetricRow(title: "Last request footprint", value: p.footprint)
            MetricRow(title: "Configured model", value: p.configuredModel)
        }
    }
}

struct UsageSection: View {
    @ObservedObject var store: SidecarStore
    var compact = false
    var body: some View {
        let p = SessionPresentation(store.session)
        SidecarSection(title: "Observed chat usage") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    summary(value: p.observedTotal, label: "tokens")
                    Divider().frame(height: 34)
                    summary(value: store.session.map { PresentationText.number(Int64($0.requests.count)) } ?? "Unavailable", label: "completed requests")
                    Divider().frame(height: 34)
                    summary(value: p.cacheRate, label: "cache hit")
                }
                VStack(alignment: .leading, spacing: 8) {
                    summary(value: p.observedTotal, label: "tokens")
                    MetricRow(title: "Completed requests", value: store.session.map { PresentationText.number(Int64($0.requests.count)) } ?? "Unavailable")
                    MetricRow(title: "Cache hit rate", value: p.cacheRate)
                }
            }
            Text("Selected chat · Observed records only").font(.caption).foregroundStyle(.secondary)
            Text(p.reconciliation).font(.caption)
            if let count = store.session?.diagnostics.count, count > 0 {
                Text("\(count) source diagnostics · Coverage may be incomplete").font(.caption)
            }
            if !compact {
                MetricRow(title: "Input", value: PresentationText.number(store.session?.totals.input))
                MetricRow(title: "Output", value: PresentationText.number(store.session?.totals.output))
                MetricRow(title: "Cached input · Included in input", value: PresentationText.number(store.session?.totals.cachedInput))
            }
            DisclosureGroup("Coverage and source details") {
                Text("Observed files may omit earlier or interrupted usage. Cached input is included in input; reasoning is included in output.")
                UsageBreakdown(usage: store.session?.totals)
                MetricRow(title: "Reported cumulative · Separate source value", value: p.reportedCumulative)
            }.font(.caption)
        }
    }
    private func summary(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().textSelection(.enabled)
                .accessibilityLabel("\(label): \(value)")
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }
}
struct MetricRow: View {
    let title: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).monospacedDigit().textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).monospacedDigit().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine).accessibilityLabel("\(title): \(value)")
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
            DisclosureGroup("Tool calls (\(request.tools.count))") {
                PagedDetails(values: request.tools) { ToolRow(tool: $0) }
            }.font(.caption)
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
