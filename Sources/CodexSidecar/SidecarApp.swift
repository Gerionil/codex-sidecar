import SwiftUI
import AppKit
import SidecarCore

@MainActor
final class SidecarApplicationDelegate: NSObject, NSApplicationDelegate {
    var store: SidecarStore?
    private var wakeObserver: NSObjectProtocol?
    private var quitting = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.store?.wake() }
            }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
        Task { @MainActor in
            await store?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
@MainActor
struct SidecarApp: App {
    @NSApplicationDelegateAdaptor(SidecarApplicationDelegate.self) private var delegate
    @StateObject private var store: SidecarStore
    init() {
        let args = ProcessInfo.processInfo.arguments
        let isolated = args.contains("--isolated-settings")
        let persistence = isolated ? nil : SettingsPersistence()
        var settings = persistence?.load() ?? LocalSettings()
        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        if let root = value("--codex-root") { settings.rootOverride = root }
        if let executable = value("--codex-executable") { settings.executableOverride = executable }
        if args.contains("--offline") { settings.offline = true }
        let shared = SidecarStore(settings: settings, persistence: persistence)
        _store = StateObject(wrappedValue: shared)
        delegate.store = shared
        Task { await shared.start() }
    }
    var body: some Scene {
        Window("Codex Sidecar", id: "companion") {
            CompanionView(store: store)
                .preferredColorScheme(store.settings.appearance.colorScheme)
                .frame(minWidth: 320, minHeight: 400)
        }
        .defaultSize(width: 420, height: 720)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            MenuBarView(store: store)
                .modifier(SidecarPanelAppearance(appearance: store.settings.appearance))
        } label: {
            Image(nsImage: SidecarBrand.menuBarImage)
                .accessibilityLabel("Codex Sidecar")
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(store: store)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
    }
}
