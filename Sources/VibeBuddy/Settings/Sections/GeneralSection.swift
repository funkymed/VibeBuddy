import SwiftUI
import VibeBuddyKit

/// Language, and the login item.
struct GeneralSection: View {
    @Bindable var l10n: Localisation
    let onLanguageChange: () -> Void

    @State private var loginItem = StartAtLogin.state()

    private var s: SettingsStrings { l10n.settings }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: s.system) {
                SettingsRow(
                    title: s.startAtLogin,
                    hint: loginItem.isAvailable ? nil : s.startAtLoginUnavailable
                ) {
                    // Do not bind `$loginItem.isEnabled`: `SMAppService` owns this
                    // value, and storing the requested one makes the switch lie.
                    Toggle(s.startAtLogin, isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem = StartAtLogin.set($0) }))
                        .labelsHidden()
                        .disabled(!loginItem.isAvailable)
                }

                Divider()

                SettingsRow(
                    title: s.language,
                    hint: l10n.language == .system
                        ? l10n.strings.settingsLanguageSystem(l10n.effective.displayName)
                        : nil
                ) {
                    // Do not assign `l10n.language` directly: only `set(_:)` swaps
                    // the catalogue, and `onLanguageChange()` rebuilds what
                    // observes nothing — the AppKit menus and the notch.
                    Picker(s.language, selection: Binding(
                        get: { l10n.language },
                        set: { l10n.set($0); onLanguageChange() }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
        }
    }
}
