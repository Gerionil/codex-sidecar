import SwiftUI
import AppKit
import SidecarCore

struct MenuBarView: View {
    @ObservedObject var store: SidecarStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Codex Sidecar").font(.headline)
                    Spacer()
                    Button("Open window") {
                        openWindow(id: "companion")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                ChatSelector(store: store)
                QuotaSection(store: store)
                ContextSection(store: store)
                UsageSection(store: store)
                HStack {
                    Button("Refresh") { Task { await store.refreshQuotas() } }.keyboardShortcut("r")
                    SettingsLink { Text("Settings") }
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
                }
            }.padding()
        }.frame(width: 380, height: 620)
    }
}
