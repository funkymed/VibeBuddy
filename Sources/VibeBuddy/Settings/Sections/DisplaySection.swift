import SwiftUI
import VibeBuddyKit

/// What the pill and the panel put on screen.
///
/// The buddy's pixel grain and its size used to be sliders here. Both are gone:
/// they are fixed at the values the faces are drawn for — grain 3
/// (`BuddyView.pixelSize`), size 100 % of the manifest (`PillLayout.resolve`) —
/// and every other setting they could take made the buddy read worse. A
/// preference whose good value is known is a way of getting it wrong.
struct DisplaySection: View {
    @Bindable var l10n: Localisation
    @Bindable var layout: LayoutPrefs

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: l10n.settings.usage.title) {
                SettingsRow(title: s.showPillWithoutSession) {
                    Toggle(s.showPillWithoutSession, isOn: $layout.showPillWithoutSession).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.showUsage) {
                    Toggle(s.showUsage, isOn: $layout.showUsage).labelsHidden()
                }
            }
        }
    }
}
