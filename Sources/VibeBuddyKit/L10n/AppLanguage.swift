import Foundation

/// Which language the interface speaks. `.system` stores the case, not the
/// resolved value, so the app follows a system language change.
public enum AppLanguage: String, Sendable, Equatable, CaseIterable, Codable {
    case system
    case french = "fr"
    case english = "en"

    public var displayName: String {
        switch self {
        case .system:  return "Système"
        case .french:  return "Français"
        case .english: return "English"
        }
    }

    /// The concrete language this resolves to. Anything that is not French falls
    /// back to English rather than to a partial match.
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
