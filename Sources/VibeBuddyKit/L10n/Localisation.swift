import Foundation
import Observation

/// The current language, and the strings that go with it. Observable so a
/// change in preferences redraws the interface rather than waiting for a relaunch.
@MainActor
@Observable
public final class Localisation {

    public static let storageKey = "vibebuddy.language"

    public private(set) var language: AppLanguage
    public private(set) var strings: Strings

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Nothing stored means `.system`, which is what following macOS means.
        let stored = defaults.string(forKey: Self.storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.language = stored
        self.strings = Strings.for(stored)
    }

    public func set(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        self.strings = Strings.for(language)
        defaults.set(language.rawValue, forKey: Self.storageKey)
    }

    /// What `.system` currently resolves to. Shown next to the picker.
    public var effective: AppLanguage { language.resolved() }

    public var locale: Locale { language.locale }

    /// The settings window's catalogue, resolved the same way as the panel's.
    public var settings: SettingsStrings {
        effective == .french ? .french : .english
    }
}
