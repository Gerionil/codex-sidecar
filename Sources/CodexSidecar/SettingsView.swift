import SwiftUI
import SidecarCore

struct SettingsView: View {
    @ObservedObject var store: SidecarStore
    @State private var root = ""
    @State private var executable = ""
    @State private var applying = false
    private var valid: Bool {
        [root, executable].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") }
    }
    var body: some View {
        Form {
            Picker("Appearance", selection: Binding(get: { store.settings.appearance }, set: { store.setAppearance($0) })) {
                ForEach(SidecarAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
            }.accessibilityLabel("Appearance")
            TextField("Codex root override", text: $root).accessibilityLabel("Codex root override")
            TextField("Codex executable override", text: $executable).accessibilityLabel("Codex executable override")
            Text("Use absolute paths. Leave blank for automatic resolution.").font(.caption)
            Text("Chosen root: \(store.chosenRoot)").font(.caption).textSelection(.enabled)
            Text(store.compatibility).font(.caption)
            ChatSelector(store: store)
            Toggle("Offline mode", isOn: Binding(get: { store.settings.offline }, set: { value in Task { await store.setOffline(value) } }))
            Text("Offline stops quota work; local session updates continue. Only overrides, selection, appearance and offline preference are saved.").font(.caption)
            if !valid { Text("Enter an absolute path beginning with /.").foregroundStyle(.red) }
            Button(applying ? "Applying…" : "Apply settings") {
                applying = true
                Task {
                    await store.applySettings(root: root, executable: executable)
                    applying = false
                }
            }.disabled(!valid || applying)
        }
        .formStyle(.grouped)
        .padding()
        .modifier(SidecarSurface())
        .frame(width: 520)
        .onAppear { root = store.settings.rootOverride ?? ""; executable = store.settings.executableOverride ?? "" }
    }
}
