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
                    Toggle("", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem = StartAtLogin.set($0) }))
                        .labelsHidden()
                        .disabled(!loginItem.isAvailable)
                }

                Divider()

                SettingsRow(
                    title: s.language,
                    // What `.system` means *today*, so the choice is not a guess.
                    hint: l10n.language == .system
                        ? l10n.strings.settingsLanguageSystem(l10n.effective.displayName)
                        : nil
                ) {
                    Picker("", selection: Binding(
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
