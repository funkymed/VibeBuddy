import AppKit
import SwiftUI
import VibeBuddyKit

/// Look at every expression of the buddy, and click one to see it move.
struct BuddySection: View {
    @Bindable var l10n: Localisation
    @Bindable var appearance: AppearancePrefs

    @State private var available: [BuddyManifest] = []
    @State private var selectedExpression: BuddyExpression = .idle

    private var s: SettingsStrings { l10n.settings }

    /// The manifest as it will be drawn.
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

    private func reload() {
        available = BuddyLoader.available()
    }

    /// Only the expressions the manifest actually declares: showing the six names when a
    /// file defines three is showing three faces that are really `idle` under another
    /// label.
    private func declared(in manifest: BuddyManifest) -> [BuddyExpression] {
        BuddyExpression.allCases.filter { manifest.expressions[$0.rawValue] != nil }
    }
}
