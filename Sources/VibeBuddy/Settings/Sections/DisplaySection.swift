import SwiftUI
import NotchBuddyKit

/// What the pill and the panel put on screen.
struct DisplaySection: View {
    @Bindable var l10n: Localisation
    @Bindable var layout: LayoutPrefs
    @Bindable var appearance: AppearancePrefs

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: l10n.settings.usage.title) {
                SettingsRow(title: s.showPillWithoutSession) {
                    Toggle("", isOn: $layout.showPillWithoutSession).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.showUsage) {
                    Toggle("", isOn: $layout.showUsage).labelsHidden()
                }
                Divider()
                // Bounded, and shown as its value: past three the kaomoji stop
                // being legible, so the slider cannot go there.
                SettingsRow(title: s.pixelSize) {
                    HStack(spacing: 10) {
                        Slider(value: $appearance.pixelSize, in: 1...3, step: 0.5)
                            .frame(width: 160)
                        Text(String(format: "%.1f", appearance.pixelSize))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
    }
}
