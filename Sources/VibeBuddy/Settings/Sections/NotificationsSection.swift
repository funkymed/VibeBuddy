import SwiftUI
import VibeBuddyKit

/// Which alerts interrupt, and how they are rendered.
///
/// Every toggle here silences something that already exists. Nothing on this
/// page is a placeholder for a feature RFC-012 has not written — the three
/// events are exactly the three `SessionAlert.Kind` cases the state machine can
/// produce today.
struct NotificationsSection: View {
    @Bindable var l10n: Localisation
    @Bindable var prefs: NotificationPrefs

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: l10n.settings.notifications.title) {
                SettingsRow(title: s.alertOnFinished) {
                    Toggle("", isOn: $prefs.onFinished).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.alertOnFailed) {
                    Toggle("", isOn: $prefs.onFailed).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.alertOnNeedsAttention) {
                    Toggle("", isOn: $prefs.onNeedsAttention).labelsHidden()
                }
            }

            SettingsGroup(title: s.quietWhenFrontmost) {
                SettingsRow(title: s.quietWhenFrontmost, hint: s.quietHint) {
                    Toggle("", isOn: $prefs.quietWhenFrontmost).labelsHidden()
                }
            }

            SettingsGroup(title: s.voice) {
                SettingsRow(title: s.voice, hint: s.voiceHint) {
                    Toggle("", isOn: $prefs.voice).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.haptics) {
                    Toggle("", isOn: $prefs.haptics).labelsHidden()
                }
            }
        }
    }
}
