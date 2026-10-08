import SwiftUI
import SidecarCore

struct PagedDetails<Value, Row: View>: View {
    let values: [Value]
    @ViewBuilder var row: (Value) -> Row
    @State private var selectedPage = 0
    var body: some View {
        let page = DetailPage(values, page: selectedPage)
        VStack(alignment: .leading, spacing: 8) {
            if page.rows.isEmpty { Text("No activity observed").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(page.rows.enumerated()), id: \.offset) { _, value in row(value) }
                .id(page.index)
            if page.pageCount > 1 {
                HStack {
                    Button("Previous") { selectedPage = page.index - 1 }.disabled(!page.hasPrevious)
                    Spacer()
                    Text("\(page.index + 1) / \(page.pageCount)").font(.caption).monospacedDigit()
                    Spacer()
                    Button("Next") { selectedPage = page.index + 1 }.disabled(!page.hasNext)
                }.controlSize(.small)
            }
        }
    }
}

struct TaskActivityView: View {
    let session: DerivedSession
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task activity").font(.headline)
            Text("\(session.tasks.count) observed tasks · \(session.unattributedTools.count) unattributed tool calls")
                .font(.caption).textSelection(.enabled)
            Text(statusSummary).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            DisclosureGroup("Tasks (\(session.tasks.count))") {
                PagedDetails(values: session.tasks) { task in
                    Text(taskText(task)).font(.caption).textSelection(.enabled)
                }
            }
            DisclosureGroup("Unattributed tool calls (\(session.unattributedTools.count))") {
                Text("No individual token cost · Association unavailable").font(.caption)
                PagedDetails(values: session.unattributedTools) { ToolRow(tool: $0) }
            }
        }
    }
    private var statusSummary: String {
        var counts = [0, 0, 0, 0]
        for task in session.tasks {
            switch task.status {
            case .active: counts[0] += 1
            case .completed: counts[1] += 1
            case .interrupted: counts[2] += 1
            case .unknown: counts[3] += 1
            }
        }
        return "\(counts[0]) active · \(counts[1]) completed · \(counts[2]) interrupted · \(counts[3]) unknown"
    }
    private func taskText(_ task: DerivedTask) -> String {
        let status: String
        switch task.status {
        case .active: status = "Active"
        case .completed: status = "Completed"
        case .interrupted: status = "Interrupted"
        case .unknown: status = "Unknown lifecycle"
        }
        return "\(task.taskID) · \(status) · "
            + (task.usageReported ? "\(task.requestKeys.count) completed model requests" : "Usage not reported")
            + (task.hasStart ? "" : " · Start not observed")
    }
}
