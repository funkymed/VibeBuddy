import SwiftUI
import VibeBuddyKit

/// Which build is reading the files on disk.
struct AboutSection: View {
    @Bindable var l10n: Localisation
    @Bindable var appearance: AppearancePrefs

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

            SettingsGroup(title: s.about.title) {
                SettingsRow(title: s.activeBuddy) {
                    Text(appearance.buddyID)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                Divider()
                SettingsRow(title: s.buddy.title, hint: BuddyLoader.searchPath) {
                    EmptyView()
                }
            }

            SettingsGroup(title: s.credits) {
                SettingsRow(title: s.author) {
                    Text(Self.author)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Divider()
                SettingsRow(title: s.creditsBody) { EmptyView() }
            }
        }
    }
}
