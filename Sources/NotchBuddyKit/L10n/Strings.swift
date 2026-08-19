import Foundation

/// Every user-facing string, in every language.
///
/// # Why a struct rather than `.strings` files
///
/// A missing key in a `.strings` file is a runtime miss: the app shows the raw
/// key, or silently falls back to another language, and nobody notices until a
/// user does. Here every language is an instance of the same struct, so
/// **adding a string without translating it does not compile**.
///
/// The trade is real: this is not a file a translator can edit. At two
/// languages in a personal tool that is the right way round, and the day a
/// third arrives with someone else writing it, the catalogue can move to
/// `.strings` without the call sites changing.
public struct Strings: Sendable {

    // Header
    public let noSessions: String
    public let sessionsIdle: @Sendable (Int) -> String
    public let sessionsWorking: @Sendable (Int) -> String
    public let sessionsWaiting: @Sendable (Int) -> String
    public let quit: String

    // Sessions
    public let sessionsTitle: String
    public let filterPlaceholder: String
    public let emptyHint: String
    public let noMatch: @Sendable (String) -> String
    public let since: @Sendable (String) -> String
    public let sessionHistory: @Sendable (Int) -> String
    public let contextTooltip: @Sendable (Int, Int) -> String

    // Usage
    public let usageTitle: String
    public let usageSession: String
    public let usageWeek: String
    public let usageLoading: String
    public let usageRateLimited: String
    public let usageSignedOut: String

    // Settings
    public let settingsLanguage: String
    public let settingsLanguageSystem: @Sendable (String) -> String
    public let settingsBuddy: String
    public let settingsBuddyHint: String
    public let settings: String
    public let settingsOpenFolder: String

    // Alerts
    public let alertFinished: String
    public let alertFailed: String

    public static let french = Strings(
        noSessions: "aucune session",
        sessionsIdle: { "\($0) au repos" },
        sessionsWorking: { "\($0) en cours" },
        sessionsWaiting: { "\($0) en attente" },
        quit: "Quitter notch-buddy",
        sessionsTitle: "SESSIONS",
        filterPlaceholder: "Filtrer les sessions…",
        emptyHint: "Aucune session. Lancez un agent dans un projet.",
        noMatch: { "Aucune session ne correspond à « \($0) »." },
        since: { "depuis \($0)" },
        sessionHistory: { "\($0) sessions dans ce dossier" },
        contextTooltip: { "\($0) / \($1) jetons" },
        usageTitle: "CONSOMMATION",
        usageSession: "session",
        usageWeek: "semaine",
        usageLoading: "lecture…",
        usageRateLimited: "limité",
        usageSignedOut: "non connecté",
        settingsLanguage: "Langue",
        settingsLanguageSystem: { "Suit macOS : \($0)" },
        settingsBuddy: "Buddy",
        settingsBuddyHint: "Un fichier .buddy par personnage, rechargé à l'enregistrement.",
        settings: "Réglages",
        settingsOpenFolder: "Ouvrir le dossier",
        alertFinished: "terminé",
        alertFailed: "erreur"
    )

    public static let english = Strings(
        noSessions: "no sessions",
        sessionsIdle: { "\($0) idle" },
        sessionsWorking: { "\($0) working" },
        sessionsWaiting: { "\($0) waiting" },
        quit: "Quit notch-buddy",
        sessionsTitle: "SESSIONS",
        filterPlaceholder: "Filter sessions…",
        emptyHint: "No sessions. Start an agent in a project.",
        noMatch: { "No session matches “\($0)”." },
        since: { "up \($0)" },
        sessionHistory: { "\($0) sessions in this folder" },
        contextTooltip: { "\($0) / \($1) tokens" },
        usageTitle: "USAGE",
        usageSession: "session",
        usageWeek: "week",
        usageLoading: "loading…",
        usageRateLimited: "rate limited",
        usageSignedOut: "signed out",
        settingsLanguage: "Language",
        settingsLanguageSystem: { "Follows macOS: \($0)" },
        settingsBuddy: "Buddy",
        settingsBuddyHint: "One .buddy file per character, reloaded on save.",
        settings: "Settings",
        settingsOpenFolder: "Open folder",
        alertFinished: "done",
        alertFailed: "error"
    )

    public static func `for`(_ language: AppLanguage) -> Strings {
        switch language.resolved() {
        case .french: return french
        default:      return english
        }
    }
}
