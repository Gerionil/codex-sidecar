import SwiftUI
import AppKit
import SidecarCore

struct MenuBarView: View {
    @ObservedObject var store: SidecarStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Codex Sidecar").font(.headline)
                Spacer()
                SidecarActions(store: store)
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ChatSelector(store: store)
                    Divider()
                    QuotaSection(store: store)
                    Divider()
                    UsageSection(store: store, compact: true)
                    Divider()
                    ContextSection(store: store, compact: true)
                }.padding(16)
            }
            Divider()
            HStack(spacing: 12) {
                Button {
                    openWindow(id: "companion")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open window", systemImage: "arrow.up.forward.square")
                        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                }
                    .modifier(SidecarControl())
                Spacer(minLength: 0)
                Toggle("Offline", isOn: Binding(get: { store.settings.offline }, set: { value in
                    Task { await store.setOffline(value) }
                })).toggleStyle(.checkbox).accessibilityLabel("Offline mode")
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }.padding(16)
        }.frame(width: 380, height: 620)
            .modifier(SidecarSurface())
    }
}
