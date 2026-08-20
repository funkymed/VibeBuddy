import SwiftUI
import NotchBuddyKit

/// Which build is reading the files on disk.
///
/// It earns its page for the reason the panel's identity line earns its row:
/// buddies and preferences outlive a build, and the first useful question when
/// one behaves oddly is which binary is reading them.
struct AboutSection: View {
    @Bindable var l10n: Localisation
    @Bindable var appearance: AppearancePrefs

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppName.display).font(.system(size: 20, weight: .semibold))
                Text(AppVersion.short)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(title: s.about.title) {
                SettingsRow(title: s.activeBuddy) {
                    Text(appearance.buddyID)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Divider()
                SettingsRow(title: s.buddy.title, hint: BuddyLoader.searchPath) {
                    EmptyView()
                }
            }

            SettingsGroup(title: s.credits) {
                SettingsRow(title: s.creditsBody) { EmptyView() }
            }
        }
    }
}
