import SwiftUI
import SidecarCore

struct ChatBrowser: View {
    @ObservedObject var store: SidecarStore
    var dismiss: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private var matches: [SessionDescriptor] {
        PresentationText.matchingChats(store.sessions, labels: store.sessionLabels, query: query)
    }
    var body: some View {
        let matches = matches
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a chat").font(.headline)
            TextField("Search chats or projects", text: $query)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
                .accessibilityLabel("Search chats or projects")
            if let id = store.selectedID, !store.sessions.contains(where: { $0.id == id }) {
                Text("Pinned chat · Sources unavailable").font(.caption)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if matches.isEmpty { Text("No matching chats").foregroundStyle(.secondary).padding(.vertical, 8) }
                    ForEach(matches, id: \.id) { chat in
                        Button { choose(chat.id) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark")
                                    .opacity(store.selectedID == chat.id ? 1 : 0).frame(width: 14)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.sessionTitles[chat.id] ?? chat.id).lineLimit(2)
                                    Text("\(chat.projectName ?? "Unknown project") · \(PresentationText.compactTime(chat.lastActivity)) · \(chat.provenanceAmbiguous ? "Ambiguous provenance" : (chat.parentThreadID == nil ? "Root" : "Child"))")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(store.selectedID == chat.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                            .help(store.sessionLabels[chat.id] ?? chat.id)
                            .accessibilityLabel(store.sessionLabels[chat.id] ?? chat.id)
                            .accessibilityValue(store.selectedID == chat.id ? "Selected" : "")
                    }
                }
            }
            Text("\(matches.count) chats · Recent activity first within roots and children")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(14).frame(width: 360, height: 420)
            .modifier(SidecarSurface())
            .onAppear { searchFocused = true }
            .onExitCommand { dismiss() }
    }
    private func choose(_ id: String) {
        dismiss()
        Task { await store.selectSession(id: id) }
    }
}
