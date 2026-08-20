import AppKit
import SwiftUI
import VibeBuddyKit

/// The things one needs once, and needs badly.
struct AdvancedSection: View {
    @Bindable var l10n: Localisation
    let onReset: () -> Void

    @State private var confirming = false

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: s.buddy.title) {
                SettingsRow(title: s.openBuddyFolder, hint: BuddyLoader.searchPath) {
                    Button(s.openBuddyFolder) {
                        let path = BuddyLoader.searchPath
                        try? FileManager.default.createDirectory(
                            atPath: path, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .pointingHandCursor()
                }
            }

            SettingsGroup(title: s.advanced.title) {
                SettingsRow(title: s.resetEverything, hint: s.resetEverythingHint) {
                    Button(s.resetEverything, role: .destructive) { confirming = true }
                        .pointingHandCursor()
                }
            }
        }
        .confirmationDialog(s.resetEverything, isPresented: $confirming) {
            Button(s.resetEverything, role: .destructive, action: onReset)
        } message: {
            Text(s.resetEverythingHint)
        }
    }
}
