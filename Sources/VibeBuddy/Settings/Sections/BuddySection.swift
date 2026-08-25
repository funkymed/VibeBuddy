import AppKit
import SwiftUI
import VibeBuddyKit

/// Look at every expression of the buddy, and click one to see it move.
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
///
/// **The picker was removed on 2026-08-24.** There is exactly one buddy — `eve`,
/// embedded in the binary — so the control offered a choice of one, which reads
/// as a promise the product does not keep. The `.buddy` format stays for what it
/// actually earns: hot reload while a face is being drawn, no relaunch and no
/// recompilation. Dropping a second file in the folder still works; the day
/// there is one, the picker comes back.
struct BuddySection: View {
    @Bindable var l10n: Localisation
    @Bindable var appearance: AppearancePrefs

    @State private var available: [BuddyManifest] = []
    @State private var selectedExpression: BuddyExpression = .idle

    private var s: SettingsStrings { l10n.settings }

    /// The manifest as it will be drawn.
    ///
    /// Looked up by id rather than taken as « the first one »: the id is what
    /// `AppearancePrefs` has stored and what the pill loads, so reading it here
    /// keeps the preview and the notch on the same file even when the folder
    /// holds several.
    private var manifest: BuddyManifest? {
        guard let base = available.first(where: { $0.id == appearance.buddyID })
            ?? available.first
        else { return nil }
        return base
    }

    var body: some View {
        SettingsPage {
            if let manifest {
                BuddyPreviewStrip(
                    manifest: manifest, expressions: declared(in: manifest),
                    selection: $selectedExpression)
            }
            Text(s.buddyFolder)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: reload)
    }

    // MARK: - Pieces

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
