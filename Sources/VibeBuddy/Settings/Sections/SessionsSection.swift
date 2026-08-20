import SwiftUI
import VibeBuddyKit

/// How the session list behaves.
struct SessionsSection: View {
    @Bindable var l10n: Localisation
    @Bindable var prefs: LayoutPrefs

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: l10n.strings.sessionsTitle) {
                SettingsRow(title: s.groupByDirectory, hint: s.groupByDirectoryHint) {
                    Toggle(s.groupByDirectory, isOn: $prefs.groupByDirectory).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.jumpOnClick, hint: s.jumpOnClickHint) {
                    Toggle(s.jumpOnClick, isOn: $prefs.jumpOnClick).labelsHidden()
                }
            }
        }
    }
}
