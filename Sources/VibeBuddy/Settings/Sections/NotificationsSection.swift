import SwiftUI
import VibeBuddyKit

/// Which alerts interrupt, and how they are rendered.
struct NotificationsSection: View {
    @Bindable var l10n: Localisation
    @Bindable var prefs: NotificationPrefs

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: l10n.settings.notifications.title) {
                SettingsRow(title: s.alertOnFinished) {
                    Toggle(s.alertOnFinished, isOn: $prefs.onFinished).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.alertOnFailed) {
                    Toggle(s.alertOnFailed, isOn: $prefs.onFailed).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.alertOnNeedsAttention) {
                    Toggle(s.alertOnNeedsAttention, isOn: $prefs.onNeedsAttention).labelsHidden()
                }
            }

            SettingsGroup(title: s.quietWhenFrontmost) {
                SettingsRow(title: s.quietWhenFrontmost, hint: s.quietHint) {
                    Toggle(s.quietWhenFrontmost, isOn: $prefs.quietWhenFrontmost).labelsHidden()
                }
            }

            SettingsGroup(title: s.voice) {
                SettingsRow(title: s.voice, hint: s.voiceHint) {
                    Toggle(s.voice, isOn: $prefs.voice).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.haptics) {
                    Toggle(s.haptics, isOn: $prefs.haptics).labelsHidden()
                }
            }
        }
    }
}
