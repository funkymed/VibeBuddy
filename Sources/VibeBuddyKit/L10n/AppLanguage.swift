import Foundation

/// Which language the interface speaks.
///
/// `.system` is the default and follows macOS. It is a distinct case rather
/// than "whatever we resolved at launch": someone who changes their system
/// language expects the app to follow, and storing the resolved value would
/// freeze it forever.
public enum AppLanguage: String, Sendable, Equatable, CaseIterable, Codable {
    case system
    case french = "fr"
    case english = "en"

    /// Name shown in the picker, in its own language — a French speaker looking
    /// for their language scans for "Français", not for "French".
    public var displayName: String {
        switch self {
        case .system:  return "Système"
        case .french:  return "Français"
        case .english: return "English"
        }
    }

    /// The concrete language this resolves to.
    ///
    /// Anything that is not French falls back to English rather than to a
    /// partial match: a Portuguese user gets a language they can probably read,
    /// not a half-translated interface.
    public func resolved(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch self {
        case .french, .english: return self
        case .system:
            let first = preferred.first?.lowercased() ?? "en"
            return first.hasPrefix("fr") ? .french : .english
        }
    }

    /// Locale for dates and numbers, so a French interface does not print
    /// "August 23" underneath "semaine".
    public var locale: Locale {
        switch resolved() {
        case .french: return Locale(identifier: "fr_FR")
        default:      return Locale(identifier: "en_US")
        }
    }
}
