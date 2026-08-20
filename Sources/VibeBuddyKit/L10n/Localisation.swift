import Foundation
import Observation

/// The current language, and the strings that go with it.
///
/// Observable so a change in preferences redraws the interface immediately
/// rather than at the next launch — a language picker that needs a restart is a
/// language picker people distrust.
@MainActor
@Observable
public final class Localisation {

    public static let storageKey = "vibebuddy.language"

    public private(set) var language: AppLanguage
    public private(set) var strings: Strings

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // First launch has nothing stored, so `.system` applies and the
        // resolution below follows macOS. Detection is therefore not a separate
        // step — it is what `.system` *means*.
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

    /// What `.system` currently resolves to. Shown next to the picker so the
    /// user knows what "Système" means for them today.
    public var effective: AppLanguage { language.resolved() }

    public var locale: Locale { language.locale }

    /// The settings window's catalogue, in the same language as the panel.
    ///
    /// Separate struct, same resolution — a window that stayed English while the
    /// panel spoke French would look like a bug, and the two catalogues have no
    /// reason to ever disagree about which language is active.
    public var settings: SettingsStrings {
        effective == .french ? .french : .english
    }
}
