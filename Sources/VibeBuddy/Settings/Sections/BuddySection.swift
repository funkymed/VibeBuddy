import AppKit
import SwiftUI
import VibeBuddyKit

/// Choose a buddy, and look at every one of its expressions.
///
/// **The editor was removed on 2026-08-21.** It let the user change an eye's
/// shape, size and colour from here, and those edits lived in `UserDefaults`
/// rather than in the `.buddy` file — two sources of truth for one face,
/// reconciled by `BuddyOverrides.apply(to:)` on every read. The format is the
/// place to edit a buddy: it is text, it reloads on save without relaunching,
/// and it is what a third party would ship. A second, weaker editor beside it
/// was a maintenance cost for something the file already did better.
///
/// The **preview stays**. It is the fastest way to see the six faces of a
/// manifest without launching anything — including while debugging one that is
/// being written. See RFC-010, "Notes d'implémentation".
struct BuddySection: View {
    @Bindable var l10n: Localisation
    @Bindable var appearance: AppearancePrefs
    /// The pill reloads when the choice changes; without it the notch only
    /// catches up when the settings window closes.
    let onBuddyChange: (String?) -> Void

    @State private var available: [BuddyManifest] = []
    @State private var selectedExpression: BuddyExpression = .idle

    private var s: SettingsStrings { l10n.settings }

    /// The manifest as it will be drawn.
    private var manifest: BuddyManifest? {
        guard let base = available.first(where: { $0.id == appearance.buddyID })
        else { return nil }
        return appearance.resolved(base)
    }

    var body: some View {
        SettingsPage {
            picker
            if let manifest {
                BuddyPreviewStrip(
                    manifest: manifest, expressions: declared(in: manifest),
                    selection: $selectedExpression)
            }
            Text(s.buddyFolder)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(s.openBuddyFolder) {
                NSWorkspace.shared.open(URL(fileURLWithPath: BuddyLoader.searchPath))
            }
            .controlSize(.small)
        }
        .onAppear(perform: reload)
    }

    // MARK: - Pieces

    private var picker: some View {
        SettingsGroup(title: s.activeBuddy) {
            SettingsRow(title: s.activeBuddy) {
                Picker(s.activeBuddy, selection: $appearance.buddyID) {
                    ForEach(available, id: \.id) { manifest in
                        Text(manifest.name).tag(manifest.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: appearance.buddyID) { onBuddyChange(appearance.buddyID) }
            }
        }
    }

    private func reload() {
        available = BuddyLoader.available()
    }

    /// Only the expressions the manifest actually declares: showing the six
    /// names when a file defines three is showing three faces that are really
    /// `idle` under another label.
    private func declared(in manifest: BuddyManifest) -> [BuddyExpression] {
        BuddyExpression.allCases.filter { manifest.expressions[$0.rawValue] != nil }
    }
}
