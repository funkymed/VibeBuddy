import SwiftUI
import VibeBuddyKit

/// What macOS lets this app do, and how to change it.
struct PermissionsSection: View {
    @Bindable var l10n: Localisation

    @State private var items: [SystemPermissions.Item] = []

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: s.permissionsTitle) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    row(item)
                }
                if items.isEmpty {
                    Text(s.permissionsNone)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { reload() }
        // Coming back from System Settings is the only moment any of this can have
        // changed.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    /// Off the main thread, always.
    private func reload() {
        let strings = l10n.strings
        Task.detached(priority: .utility) {
            let found = SystemPermissions.all(l10n: strings)
            await MainActor.run { items = found }
        }
    }

    @ViewBuilder
    private func row(_ item: SystemPermissions.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                Text(item.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            badge(item.state)
            // Nothing to fix means no button: a button that opens a pane where there is
            // nothing to change teaches the user to distrust it.
            if needsAction(item.state), let url = item.settingsURL {
                Button(s.permissionsOpen) { NSWorkspace.shared.open(url) }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func needsAction(_ state: SystemPermissions.State) -> Bool {
        switch state {
        case .granted: return false
        case .unavailable: return false
        case .denied, .notAsked: return true
        }
    }

    private func badge(_ state: SystemPermissions.State) -> some View {
        let (text, colour): (String, Color) = {
            switch state {
            case .granted: return (s.permissionsGranted, .green)
            case .denied: return (s.permissionsDenied, .red)
            case .notAsked: return (s.permissionsNotAsked, .orange)
            case let .unavailable(reason): return (reason, .secondary)
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(colour)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(colour.opacity(0.12)))
            .fixedSize()
    }
}
