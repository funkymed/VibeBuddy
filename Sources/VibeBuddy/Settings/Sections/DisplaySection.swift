import SwiftUI
import VibeBuddyKit

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
                    Toggle(s.showPillWithoutSession, isOn: $layout.showPillWithoutSession).labelsHidden()
                }
                Divider()
                SettingsRow(title: s.showUsage) {
                    Toggle(s.showUsage, isOn: $layout.showUsage).labelsHidden()
                }
                Divider()
                // Capped at 3: past that the kaomoji stop being legible.
                SettingsRow(title: s.pixelSize) {
                    HStack(spacing: 10) {
                        Slider(value: $appearance.pixelSize, in: 1...3, step: 0.5)
                            .frame(width: 160)
                            .accessibilityLabel(s.pixelSize)
                        Text(String(format: "%.1f", appearance.pixelSize))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                    }
                }
            }
        }
    }
}
