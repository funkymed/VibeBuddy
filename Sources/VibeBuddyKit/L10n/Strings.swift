import Foundation

/// Every user-facing string, in every language.
///
/// Every language is an instance of the same struct, so adding a string without
/// translating it does not compile. See RFC-001, "Notes d'implémentation".
public struct Strings: Sendable {

    // Header
    public let noSessions: String
    public let sessionsIdle: @Sendable (Int) -> String
    public let sessionsWorking: @Sendable (Int) -> String
    public let sessionsWaiting: @Sendable (Int) -> String
    /// Bare state word: the header's compact fraction supplies the count.
    public let stateWorking: String
    public let stateIdle: String
    public let stateAwaiting: String
    public let stateFinished: String
    public let stateFailed: String
    public let stateEnded: String
    public let quit: String

    // Sessions
    public let sessionsTitle: String
    public let filterPlaceholder: String
    public let emptyHint: String
    public let noMatch: @Sendable (String) -> String
    public let since: @Sendable (String) -> String
    public let sessionHistory: @Sendable (Int) -> String
    public let contextTooltip: @Sendable (Int, Int) -> String
    public let jumpHint: String
    /// Shown when the click found the terminal but not the tab — under tmux, or
    /// on an emulator with no scripting dictionary.
    public let jumpNoTab: String
    public let jumpNoTerminal: String
    public let jumpFailed: @Sendable (String) -> String

    // Usage
    public let usageTitle: String
    public let usageSession: String
    public let usageWeek: String
    public let usageLoading: String
    public let usageRateLimited: String
    public let usageAge: @Sendable (String) -> String
    public let usageSignedOut: String

    // Settings
    public let settingsLanguage: String
    public let settingsLanguageSystem: @Sendable (String) -> String
    public let settingsBuddy: String
    public let settingsBuddyHint: String
    public let settings: String
    public let settingsOpenFolder: String

    // Tool labels — one per `ToolLabel` case. Reached through `label(for:)`.
    public let toolShell: String
    public let toolEditing: String
    public let toolWriting: String
    public let toolReading: String
    public let toolSearching: String
    public let toolListing: String
    public let toolWeb: String
    public let toolWebSearch: String
    public let toolDelegating: String
    public let toolPlanning: String
    public let toolNotebook: String
    public let toolQuestion: String

    // Alerts
    public let alertFinished: String
    public let alertFailed: String
    public let alertWaiting: String

    public static let french = Strings(
        noSessions: "aucune session",
        sessionsIdle: { "\($0) au repos" },
        sessionsWorking: { "\($0) en cours" },
        sessionsWaiting: { "\($0) en attente" },
        stateWorking: "en cours",
        stateIdle: "au repos",
        stateAwaiting: "question",
        stateFinished: "terminé",
        stateFailed: "erreur",
        stateEnded: "arrêtée",
        quit: "Quitter " + AppName.display,
        sessionsTitle: "SESSIONS",
        filterPlaceholder: "Filtrer les sessions…",
        emptyHint: "Aucune session. Lancez un agent dans un projet.",
        noMatch: { "Aucune session ne correspond à « \($0) »." },
        since: { "depuis \($0)" },
        sessionHistory: { "\($0) sessions dans ce dossier" },
        contextTooltip: { "\($0) / \($1) jetons" },
        jumpHint: "Cliquer pour revenir à ce terminal",
        jumpNoTab: "Terminal activé — onglet introuvable (tmux ?)",
        jumpNoTerminal: "Aucun terminal trouvé pour cette session",
        jumpFailed: { "Saut impossible : \($0)" },
        usageTitle: "CONSOMMATION",
        usageSession: "session",
        usageWeek: "semaine",
        usageLoading: "lecture…",
        usageRateLimited: "limité",
        usageAge: { "il y a \($0)" },
        usageSignedOut: "non connecté",
        settingsLanguage: "Langue",
        settingsLanguageSystem: { "Suit macOS : \($0)" },
        settingsBuddy: "Buddy",
        settingsBuddyHint: "Un fichier .buddy par personnage, rechargé à l'enregistrement.",
        settings: "Réglages",
        settingsOpenFolder: "Ouvrir le dossier",
        toolShell: "commande",
        toolEditing: "édition",
        toolWriting: "écriture",
        toolReading: "lecture",
        toolSearching: "recherche",
        toolListing: "listage",
        toolWeb: "web",
        toolWebSearch: "recherche web",
        toolDelegating: "délégation",
        toolPlanning: "plan",
        toolNotebook: "notebook",
        toolQuestion: "question",
        alertFinished: "terminé",
        alertFailed: "erreur",
        alertWaiting: "attend une réponse"
    )

    public static let english = Strings(
        noSessions: "no sessions",
        sessionsIdle: { "\($0) idle" },
        sessionsWorking: { "\($0) working" },
        sessionsWaiting: { "\($0) waiting" },
        stateWorking: "working",
        stateIdle: "idle",
        stateAwaiting: "question",
        stateFinished: "done",
        stateFailed: "error",
        stateEnded: "ended",
        quit: "Quit " + AppName.display,
        sessionsTitle: "SESSIONS",
        filterPlaceholder: "Filter sessions…",
        emptyHint: "No sessions. Start an agent in a project.",
        noMatch: { "No session matches “\($0)”." },
        since: { "up \($0)" },
        sessionHistory: { "\($0) sessions in this folder" },
        contextTooltip: { "\($0) / \($1) tokens" },
        jumpHint: "Click to go back to this terminal",
        jumpNoTab: "Terminal activated — tab not found (tmux?)",
        jumpNoTerminal: "No terminal found for this session",
        jumpFailed: { "Jump failed: \($0)" },
        usageTitle: "USAGE",
        usageSession: "session",
        usageWeek: "week",
        usageLoading: "loading…",
        usageRateLimited: "rate limited",
        usageAge: { "\($0) ago" },
        usageSignedOut: "signed out",
        settingsLanguage: "Language",
        settingsLanguageSystem: { "Follows macOS: \($0)" },
        settingsBuddy: "Buddy",
        settingsBuddyHint: "One .buddy file per character, reloaded on save.",
        settings: "Settings",
        settingsOpenFolder: "Open folder",
        toolShell: "command",
        toolEditing: "editing",
        toolWriting: "writing",
        toolReading: "reading",
        toolSearching: "searching",
        toolListing: "listing",
        toolWeb: "web",
        toolWebSearch: "web search",
        toolDelegating: "delegating",
        toolPlanning: "planning",
        toolNotebook: "notebook",
        toolQuestion: "question",
        alertFinished: "done",
        alertFailed: "error",
        alertWaiting: "needs an answer"
    )

    /// Single translation point for `ToolLabel`; without it every view duplicates the switch.
    public func label(for tool: ToolLabel) -> String {
        switch tool {
        case .shell:      return toolShell
        case .editing:    return toolEditing
        case .writing:    return toolWriting
        case .reading:    return toolReading
        case .searching:  return toolSearching
        case .listing:    return toolListing
        case .web:        return toolWeb
        case .webSearch:  return toolWebSearch
        case .delegating: return toolDelegating
        case .planning:   return toolPlanning
        case .notebook:   return toolNotebook
        case .question:   return toolQuestion
        case .other(let name): return name
        }
    }

    public static func `for`(_ language: AppLanguage) -> Strings {
        switch language.resolved() {
        case .french: return french
        default:      return english
        }
    }
}
