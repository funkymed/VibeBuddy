import AppKit
import SwiftUI
import VibeBuddyKit

/// Which build is reading the files on disk, and whether a newer one exists.
struct AboutSection: View {
    @Bindable var l10n: Localisation
    @Bindable var updates: UpdateState

    @State private var checking = false

    private var s: SettingsStrings { l10n.settings }

    /// Not translated: a handle is a handle in every language.
    private static let author = "@funkymed"

    var body: some View {
        SettingsPage {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppName.display).font(.title2.weight(.semibold))
                Text(AppVersion.short)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(title: s.updateGroup) {
                SettingsRow(title: status, hint: hint) {
                    if let release = updates.available {
                        Button(s.updateOpen) { NSWorkspace.shared.open(release.page) }
                            .pointingHandCursor()
                    } else {
                        Button(s.updateCheckNow) { Task { await checkNow() } }
                            .disabled(checking || !updates.isEnabled)
                            .pointingHandCursor()
                    }
                }
            }

            SettingsGroup(title: s.credits) {
                SettingsRow(title: s.author) {
                    Text(Self.author)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// The one line that says what is known.
    private var status: String {
        if checking { return s.updateChecking }
        if let release = updates.available {
            return s.updateAvailable(release.version.description)
        }
        return updates.lastCheck == nil ? s.updateNever : s.updateUpToDate
    }

    /// How to act on it when there is something to act on, and how stale the answer is
    /// otherwise. The install line is spelled out because this app cannot install
    /// itself: it is not notarised, so a binary it fetched would land quarantined.
    private var hint: String? {
        if updates.available != nil { return s.updateHow }
        guard let last = updates.lastCheck else { return nil }
        return s.updateLastCheck(SessionRow.duration(since: last))
    }

    /// Forces a check past the daily interval, which is what a button labelled « check
    /// now » has to mean.
    private func checkNow() async {
        checking = true
        defer { checking = false }
        await updates.check()
    }
}
