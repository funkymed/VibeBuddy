import SwiftUI
import VibeBuddyKit

/// What macOS lets this app do, and how to change it.
///
/// The state is read **when the screen appears and when the app comes back to
/// the front** — never on a clock. Granting happens in System Settings, so the
/// user leaves and comes back: that return is the event, and waiting for it
/// costs nothing.
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
        // Coming back from System Settings is the only moment any of this can
        // have changed.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    /// **Off the main thread, always.**
    ///
    /// `SystemPermissions.all` calls `AEDeterminePermissionToAutomateTarget`
    /// once per terminal it knows about, plus `SMAppService.mainApp.status`.
    /// Both talk to system daemons — TCC and the login-item service — and both
    /// block until those answer.
    ///
    /// Run inline, that froze the whole app the moment the settings window
    /// opened, and **only in a signed bundle**: unbundled,
    /// `Bundle.main.bundleIdentifier` is nil and the automation probe returns
    /// immediately without touching TCC, so the bug was invisible in every
    /// local run and reproducible in every release. That asymmetry is the
    /// signature of a permission check, and it is worth recognising early.
    ///
    /// The `Task.detached` also matters on the second path: this reloads on
    /// every `didBecomeActive`, so the cost is paid again each time the user
    /// comes back from System Settings.
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
            // Nothing to fix means no button: a button that opens a pane where
            // there is nothing to change teaches the user to distrust it.
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
