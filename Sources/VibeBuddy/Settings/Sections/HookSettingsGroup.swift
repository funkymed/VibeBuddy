import SwiftUI
import VibeBuddyKit

/// Whether `vibe-hook` is registered in `~/.claude/settings.json`, and the one button
/// that changes it. Nothing is written without the sheet's consent (D6).
struct HookSettingsGroup: View {
    let s: SettingsStrings

    @State private var report: HookInstallReport?
    /// True to remove, false to install or repair. Nil: no sheet.
    @State private var consent: HookConsent?

    var body: some View {
        SettingsGroup(title: s.hookTitle) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.hookRow)
                        .font(.system(size: 13))
                    Text(s.hookExplanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    detail
                }
                Spacer(minLength: 12)
                if let report {
                    badge(report.state)
                    action(report.state)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear { reload() }
        // Someone may have edited the file by hand while the window was behind.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
        .sheet(item: $consent) { consent in
            HookConsentSheet(removing: consent.removing, s: s) {
                self.consent = nil
                reload()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch report?.state {
        case let .stale(path)?:
            note(s.hookStalePath(path), .orange)
        case let .unreadable(reason)?:
            note(reason, .red)
        default:
            EmptyView()
        }
        // Said, never changed: that setting belongs to Claude Code.
        if report?.asksNothing == true, report?.state == .installed {
            note(s.hookAsksNothing, .orange)
        }
    }

    private func note(_ text: String, _ colour: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func badge(_ state: HookInstallState) -> some View {
        let (text, colour): (String, Color) = switch state {
        case .installed: (s.hookInstalled, .green)
        case .missing: (s.hookMissing, .orange)
        case .stale: (s.hookStale, .orange)
        case .partial: (s.hookPartial, .orange)
        case .unreadable: (s.hookUnreadable, .red)
        }
        return SettingsStateBadge(text: text, colour: colour)
    }

    /// An unreadable file gets no button: it is never written over.
    @ViewBuilder
    private func action(_ state: HookInstallState) -> some View {
        switch state {
        case .installed:
            button(s.hookRemove, removing: true)
        case .missing:
            button(s.hookInstall, removing: false)
        case .stale, .partial:
            button(s.hookRepair, removing: false)
        case .unreadable:
            EmptyView()
        }
    }

    private func button(_ title: String, removing: Bool) -> some View {
        Button(title) { consent = HookConsent(removing: removing) }
            .controlSize(.small)
            .pointingHandCursor()
    }

    /// Off the main thread, always: the release-only freeze of 2026-08 was file and
    /// permission work done in a settings view.
    private func reload() {
        Task.detached(priority: .utility) {
            let found = HookInstaller().inspect()
            await MainActor.run { report = found }
        }
    }
}

struct HookConsent: Identifiable {
    let removing: Bool
    var id: Bool { removing }
}
