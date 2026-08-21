import SwiftUI
import VibeBuddyKit

/// What the pill and the panel put on screen.
struct DisplaySection: View {
    @Bindable var l10n: Localisation
    @Bindable var layout: LayoutPrefs
    @Bindable var appearance: AppearancePrefs
    /// Both sliders here change how the buddy is drawn, and one of them changes
    /// how wide the pill is. Without this the notch only caught up when the
    /// settings window closed, which is too late to aim a slider by.
    var onBuddyChange: (String?) -> Void = { _ in }

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
                Divider()
                // The pill is measured from the buddy's screen, so this slider
                // is what sets the collapsed width. Bounded at both ends: below
                // two thirds the eyes run out of cells, above it the ear hits
                // `PillLayout.maxSlotWidth` and the buddy is scaled back down
                // to fit — the slider would stop doing anything.
                SettingsRow(title: s.buddyScale) {
                    HStack(spacing: 10) {
                        Slider(value: $appearance.buddyScale, in: 0.65...1.35, step: 0.05)
                            .frame(width: 160)
                            .accessibilityLabel(s.buddyScale)
                        Text(String(format: "%.0f %%", appearance.buddyScale * 100))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                }
            }
        }
        .onChange(of: appearance.buddyScale) { onBuddyChange(appearance.buddyID) }
        .onChange(of: appearance.pixelSize) { onBuddyChange(appearance.buddyID) }
    }
}