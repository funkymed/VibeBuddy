import Foundation

/// Every user-facing string, in every language.
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
    /// Shown when the click found the terminal but not the tab — under tmux, or on an
    /// emulator with no scripting dictionary.
    public let jumpNoTab: String
    public let jumpNoTerminal: String
    public let jumpFailed: @Sendable (String) -> String

    // Session timeline
    public let timelineTitle: String
    public let timelineOpen: String
    public let timelineBack: String
    public let timelineEmpty: String
    /// The transcript could not be read, which is not the same as a session with
    /// nothing in it.
    public let timelineUnreadable: String
    public let timelinePrompt: String
    public let timelineResult: String
    public let timelineResultFailed: String
    public let timelineTurnEnd: @Sendable (String) -> String
    public let timelineSubagentStarted: String
    public let timelineSubagentFinished: String

    // Dismissing a session
    public let dismissTitle: String
    public let dismissHint: String
    /// Says what it does and what it does not: nothing on disk is touched.
    public let dismissBody: @Sendable (String) -> String
    public let dismissKeepsTranscript: String
    public let dismissCancel: String
    public let dismissConfirm: String
    /// How many rows are hidden, and the way back.
    public let dismissedCount: @Sendable (Int) -> String
    public let dismissedRestore: String

    /// The panel's own notice. Shorter than the settings one: it sits next to the
    /// counter, and a sentence there would push the gear off the row.
    public let updateBadge: @Sendable (String) -> String

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

    // Tool labels — one per `ToolLabel` case.
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

    // Permissions
    public let permissionAutomation: @Sendable (String) -> String
    public let permissionAutomationWhy: String
    public let permissionLoginItem: String
    public let permissionLoginItemWhy: String
    /// What a refusal tells the model.
    public let permissionDenied: String
    public let permissionTitle: String
    public let consentTitle: String
    public let consentCancel: String
    public let consentConfirm: String
    /// Told the folder where a wrong write can be undone from.
    public let consentBackup: @Sendable (String) -> String
    /// How many requests are queued behind the one on screen.
    public let permissionWaiting: @Sendable (Int) -> String
    public let permissionDeny: String
    public let permissionAllow: String
    public let permissionAlwaysAllow: String
    /// Names the file the button writes to, out loud: the consent half of R1.
    public let permissionAlwaysAllowHint: String
    /// Under an `AskUserQuestion`'s options: clicking one answers Claude, it does not
    /// grant anything.
    public let permissionAnswerHint: String
    /// What « Allow » does on a question, said as what it does.
    public let permissionAnswerInTerminal: String
    /// A diff whose left side is empty: the file does not exist yet.
    public let permissionNewFile: String
    /// A write of nothing at all — said out loud, because an empty box reads as a
    /// rendering bug rather than as an empty file.
    public let permissionNoContent: String
    /// Caption above the host: what a fetch actually grants.
    public let permissionDomain: String

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
        timelineTitle: "HISTORIQUE",
        timelineOpen: "Voir l'historique de cette session",
        timelineBack: "Retour",
        timelineEmpty: "Rien à montrer pour cette session.",
        timelineUnreadable: "Transcript illisible.",
        timelinePrompt: "message",
        timelineResult: "résultat",
        timelineResultFailed: "échec",
        timelineTurnEnd: { "fin de tour · \($0)" },
        timelineSubagentStarted: "sous-agent lancé",
        timelineSubagentFinished: "sous-agent terminé",
        dismissTitle: "RETIRER DE LA LISTE",
        dismissHint: "Retirer cette session de la liste",
        dismissBody: { "« \($0) » disparaît de la liste. Elle revient si l'agent y écrit de nouveau." },
        dismissKeepsTranscript: "Rien n'est supprimé sur le disque : le transcript reste intact.",
        dismissCancel: "Annuler",
        dismissConfirm: "Retirer",
        dismissedCount: { $0 == 1 ? "1 session masquée" : "\($0) sessions masquées" },
        dismissedRestore: "Tout réafficher",
        updateBadge: { "v\($0) disponible" },
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
        alertWaiting: "attend une réponse",
        permissionAutomation: { "Piloter \($0)" },
        permissionAutomationWhy: "Nécessaire pour ouvrir l'onglet de terminal d'une session depuis le panneau.",
        permissionLoginItem: "Ouvrir à l'ouverture de session",
        permissionLoginItemWhy: "Sans quoi il faut lancer l'app à la main après chaque redémarrage.",
        permissionDenied: "Refusé par l'utilisateur depuis VibeBuddy. N'essaie pas une autre façon de faire la même chose : demande-lui ce qu'il veut.",
        permissionTitle: "AUTORISATION",
        consentTitle: "ÉCRIRE CETTE RÈGLE DANS VOS RÉGLAGES",
        consentCancel: "Annuler",
        consentConfirm: "Écrire",
        consentBackup: { "Une sauvegarde horodatée est prise avant écriture, dans \($0)" },
        permissionWaiting: { "+\($0) en attente" },
        permissionDeny: "Refuser",
        permissionAllow: "Autoriser",
        permissionAlwaysAllow: "Toujours autoriser",
        permissionAlwaysAllowHint: "Ajoute une règle dans ~/.claude/settings.json",
        permissionAnswerHint: "Votre choix est renvoyé à Claude comme réponse.",
        permissionAnswerInTerminal: "Répondre dans le terminal",
        permissionNewFile: "nouveau fichier",
        permissionNoContent: "Aucun contenu",
        permissionDomain: "DOMAINE"
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
        timelineTitle: "HISTORY",
        timelineOpen: "Show this session's history",
        timelineBack: "Back",
        timelineEmpty: "Nothing to show for this session.",
        timelineUnreadable: "Transcript unreadable.",
        timelinePrompt: "message",
        timelineResult: "result",
        timelineResultFailed: "failed",
        timelineTurnEnd: { "turn ended · \($0)" },
        timelineSubagentStarted: "subagent started",
        timelineSubagentFinished: "subagent finished",
        dismissTitle: "REMOVE FROM THE LIST",
        dismissHint: "Remove this session from the list",
        dismissBody: { "\"\($0)\" leaves the list. It comes back if the agent writes to it again." },
        dismissKeepsTranscript: "Nothing is deleted on disk: the transcript stays intact.",
        dismissCancel: "Cancel",
        dismissConfirm: "Remove",
        dismissedCount: { $0 == 1 ? "1 hidden session" : "\($0) hidden sessions" },
        dismissedRestore: "Show all",
        updateBadge: { "v\($0) available" },
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
        alertWaiting: "needs an answer",
        permissionAutomation: { "Control \($0)" },
        permissionAutomationWhy: "Needed to open a session's terminal tab from the panel.",
        permissionLoginItem: "Open at login",
        permissionLoginItemWhy: "Without it the app has to be started by hand after every restart.",
        permissionDenied: "Refused by the user from VibeBuddy. Do not try another way to do the same thing: ask them what they want.",
        permissionTitle: "PERMISSION",
        consentTitle: "WRITE THIS RULE TO YOUR SETTINGS",
        consentCancel: "Cancel",
        consentConfirm: "Write",
        consentBackup: { "A timestamped backup is taken before writing, in \($0)" },
        permissionWaiting: { "+\($0) waiting" },
        permissionDeny: "Deny",
        permissionAllow: "Allow",
        permissionAlwaysAllow: "Always allow",
        permissionAlwaysAllowHint: "Adds a rule to ~/.claude/settings.json",
        permissionAnswerHint: "Your choice is sent back to Claude as the answer.",
        permissionAnswerInTerminal: "Answer in the terminal",
        permissionNewFile: "new file",
        permissionNoContent: "No content",
        permissionDomain: "DOMAIN"
    )

    /// Single translation point for `ToolLabel`; without it every view duplicates the
    /// switch.
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
