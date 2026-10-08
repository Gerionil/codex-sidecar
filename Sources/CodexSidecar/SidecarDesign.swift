import SwiftUI
import SidecarCore

extension SidecarAppearance {
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
    var label: String { rawValue.capitalized }
}

struct SidecarSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(scheme == .dark ? Color(red: 24/255, green: 24/255, blue: 24/255) : Color.white)
            .tint(scheme == .dark ? Color(red: 51/255, green: 156/255, blue: 1) : Color(red: 2/255, green: 133/255, blue: 1))
    }
}

/// Glass belongs to controls; numbers and source details stay on opaque surfaces.
struct SidecarControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            content.foregroundStyle(scheme == .dark ? Color.white : Color.black).buttonStyle(.glass)
        } else {
            content.foregroundStyle(scheme == .dark ? Color.white : Color.black).buttonStyle(.bordered)
        }
    }
}

struct SidecarSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidecarActions: View {
    @ObservedObject var store: SidecarStore
    var body: some View {
        HStack(spacing: 8) {
            Button { Task { await store.refreshQuotas() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }.keyboardShortcut("r").help("Refresh account limits")
                .accessibilityLabel("Refresh account limits")
            SettingsLink { Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly) }
                .help("Settings").accessibilityLabel("Settings")
        }.modifier(SidecarControl())
    }
}
