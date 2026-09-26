import Foundation

/// The settings window's own catalogue.
public struct SettingsStrings: Sendable {
    public struct Section: Sendable {
        public let title: String
        public let symbol: String
        public init(title: String, symbol: String) {
            self.title = title; self.symbol = symbol
        }
    }

    // Sidebar
    public let general: Section
    public let buddy: Section
    public let notifications: Section
    public let sessions: Section
    public let usage: Section
    public let permissions: Section
    public let advanced: Section
    public let about: Section
    public let advancedGroup: String

    // Permissions
    public let permissionsTitle: String
    public let permissionsNone: String
    public let permissionsOpen: String
    public let permissionsGranted: String
    public let permissionsDenied: String
    public let permissionsNotAsked: String

    // Permissions — the Claude Code hook
    public let hookTitle: String
    public let hookRow: String
    public let hookExplanation: String
    public let hookInstalled: String
    public let hookMissing: String
    public let hookStale: String
    public let hookPartial: String
    public let hookUnreadable: String
    public let hookStalePath: @Sendable (String) -> String
    public let hookAsksNothing: String
    public let hookInstall: String
    public let hookRepair: String
    public let hookRemove: String
    public let hookSheetInstall: String
    public let hookSheetRemove: String
    public let hookSheetFile: String
    public let hookSheetBackup: String
    public let hookSheetChanged: String
    public let hookSheetNothing: String
    public let hookSheetFailed: @Sendable (String) -> String
    public let hookCancel: String
    public let hookWrite: String

    // General
    public let system: String
    public let startAtLogin: String
    public let startAtLoginUnavailable: String
    public let language: String

    // Buddy
    public let expressions: String
    public let colour: String
    public let motion: String
    public let editedBadge: String
    public let resetExpression: String
    public let resetBuddy: String
    public let export: String
    public let exported: @Sendable (String) -> String
    public let exportFailed: @Sendable (String) -> String
    public let duplicate: String
    public let newBuddy: String
    public let deleteBuddy: String
    public let openBuddyFolder: String
    public let buddyFolder: String
    public let inherited: String

    // Notifications
    public let alertOnFinished: String
    public let alertOnFailed: String
    public let alertOnNeedsAttention: String
    public let voice: String
    public let voiceHint: String
    public let haptics: String
    public let quietWhenFrontmost: String
    public let quietHint: String

    // Sessions
    public let groupByDirectory: String
    public let groupByDirectoryHint: String
    public let jumpOnClick: String
    public let jumpOnClickHint: String

    // Usage
    public let showUsage: String
    public let showPillWithoutSession: String

    // Advanced
    public let resetEverything: String
    public let resetEverythingHint: String

    // About
    public let credits: String
    public let author: String

    // Updates
    public let updateCheck: String
    public let updateCheckHint: String
    public let updateGroup: String
    public let updateUpToDate: String
    public let updateNever: String
    public let updateChecking: String
    /// How long ago the last question was asked.
    public let updateLastCheck: @Sendable (String) -> String
    public let updateAvailable: @Sendable (String) -> String
    public let updateOpen: String
    public let updateCheckNow: String
    /// Said where it is read: `brew` is the channel, this is only the notice.
    public let updateHow: String

    public static let french = SettingsStrings(
        general: Section(title: "Général", symbol: "gearshape"),
        buddy: Section(title: "Buddy", symbol: "face.smiling"),
        notifications: Section(title: "Notifications", symbol: "bell.badge"),
        sessions: Section(title: "Sessions", symbol: "list.bullet.rectangle"),
        usage: Section(title: "Affichage", symbol: "textformat.size"),
        permissions: Section(title: "Autorisations", symbol: "lock.shield"),
        advanced: Section(title: "Avancé", symbol: "wrench.and.screwdriver"),
        about: Section(title: "À propos", symbol: "info.circle"),
        advancedGroup: "Avancé",
        permissionsTitle: "CE QUE MACOS LAISSE FAIRE À L'APP",
        permissionsNone: "Rien à autoriser sur cette machine.",
        permissionsOpen: "Ouvrir les réglages",
        permissionsGranted: "autorisé",
        permissionsDenied: "refusé",
        permissionsNotAsked: "jamais demandé",
        hookTitle: "CLAUDE CODE",
        hookRow: "Recevoir les demandes de permission",
        hookExplanation: "Déclare vibe-hook dans ~/.claude/settings.json, pour que les demandes de permission s'affichent dans la notch. Les alertes et les sessions n'en ont pas besoin.",
        hookInstalled: "installé",
        hookMissing: "absent",
        hookStale: "à réparer",
        hookPartial: "incomplet",
        hookUnreadable: "illisible",
        hookStalePath: { "Pointe vers \($0), qui n'est pas cette app." },
        hookAsksNothing: "« defaultMode » vaut « auto » dans vos réglages Claude Code : rien n'est demandé, donc rien n'arrive ici.",
        hookInstall: "Installer…",
        hookRepair: "Réparer…",
        hookRemove: "Retirer…",
        hookSheetInstall: "Installer le hook",
        hookSheetRemove: "Retirer le hook",
        hookSheetFile: "Fichier modifié",
        hookSheetBackup: "Une sauvegarde est prise avant d'écrire, dans",
        hookSheetChanged: "Le fichier a changé depuis l'ouverture. Voici le diff à jour : rien n'a été écrit.",
        hookSheetNothing: "Rien à écrire : le fichier est déjà dans cet état.",
        hookSheetFailed: { "Rien n'a été écrit : \($0)" },
        hookCancel: "Annuler",
        hookWrite: "Écrire",
        system: "Système",
        startAtLogin: "Ouvrir à l'ouverture de session",
        startAtLoginUnavailable: "Indisponible tant que l'app n'est pas empaquetée",
        language: "Langue de l'app",
        expressions: "Expressions",
        colour: "Couleur",
        motion: "Mouvement",
        editedBadge: "modifiée",
        resetExpression: "Réinitialiser cette expression",
        resetBuddy: "Réinitialiser tout le buddy",
        export: "Exporter en .buddy…",
        exported: { "Exporté vers \($0)" },
        exportFailed: { "Export impossible : \($0)" },
        duplicate: "Dupliquer",
        newBuddy: "Nouveau buddy",
        deleteBuddy: "Supprimer",
        openBuddyFolder: "Ouvrir le dossier",
        buddyFolder: "Les fichiers .buddy vivent dans le dossier ci-dessous. Les modifications faites ici sont enregistrées à part et n'y touchent pas.",
        inherited: "hérité du fichier",
        alertOnFinished: "Quand un tour se termine",
        alertOnFailed: "Quand un tour échoue",
        alertOnNeedsAttention: "Quand l'agent attend une réponse",
        voice: "Annoncer à voix haute",
        voiceHint: "Charge le moteur vocal à la première annonce (quelques Mo).",
        haptics: "Retour haptique (trackpad)",
        quietWhenFrontmost: "Rester silencieux si le terminal est au premier plan",
        quietHint: "Notifier ce qu'on regarde déjà apprend à ignorer les notifications.",
        groupByDirectory: "Regrouper les sessions par dossier",
        groupByDirectoryHint: "Une ligne par projet plutôt qu'une par transcript.",
        jumpOnClick: "Cliquer une session ouvre son terminal",
        jumpOnClickHint: "Appariement par tty. Sous tmux, l'app est activée sans choisir l'onglet.",
        showUsage: "Afficher la consommation dans le panneau",
        showPillWithoutSession: "Garder la pastille visible sans session",
        resetEverything: "Réinitialiser tous les réglages",
        resetEverythingHint: "Supprime les préférences et les modifications de buddy. Les fichiers .buddy ne sont pas touchés.",
        credits: "Crédits",
        author: "Auteur",
        updateCheck: "Chercher les mises à jour",
        updateCheckHint: "Une fois par jour, auprès de GitHub. Rien n'est téléchargé.",
        updateGroup: "Mise à jour",
        updateUpToDate: "À jour",
        updateNever: "Jamais vérifié",
        updateChecking: "Vérification…",
        updateLastCheck: { "Vérifié il y a \($0)" },
        updateAvailable: { "Version \($0) disponible" },
        updateOpen: "Voir la version",
        updateCheckNow: "Vérifier maintenant",
        updateHow: "Installer : brew upgrade --cask vibebuddy, ou le DMG de la page."
    )

    public static let english = SettingsStrings(
        general: Section(title: "General", symbol: "gearshape"),
        buddy: Section(title: "Buddy", symbol: "face.smiling"),
        notifications: Section(title: "Notifications", symbol: "bell.badge"),
        sessions: Section(title: "Sessions", symbol: "list.bullet.rectangle"),
        usage: Section(title: "Display", symbol: "textformat.size"),
        permissions: Section(title: "Permissions", symbol: "lock.shield"),
        advanced: Section(title: "Advanced", symbol: "wrench.and.screwdriver"),
        about: Section(title: "About", symbol: "info.circle"),
        advancedGroup: "Advanced",
        permissionsTitle: "WHAT MACOS LETS THE APP DO",
        permissionsNone: "Nothing to grant on this machine.",
        permissionsOpen: "Open Settings",
        permissionsGranted: "granted",
        permissionsDenied: "refused",
        permissionsNotAsked: "never asked",
        hookTitle: "CLAUDE CODE",
        hookRow: "Receive permission requests",
        hookExplanation: "Registers vibe-hook in ~/.claude/settings.json, so permission requests show up in the notch. Alerts and sessions do not need it.",
        hookInstalled: "installed",
        hookMissing: "missing",
        hookStale: "needs repair",
        hookPartial: "incomplete",
        hookUnreadable: "unreadable",
        hookStalePath: { "Points to \($0), which is not this app." },
        hookAsksNothing: "« defaultMode » is « auto » in your Claude Code settings: nothing is asked, so nothing arrives here.",
        hookInstall: "Install…",
        hookRepair: "Repair…",
        hookRemove: "Remove…",
        hookSheetInstall: "Install the hook",
        hookSheetRemove: "Remove the hook",
        hookSheetFile: "File changed",
        hookSheetBackup: "A backup is taken before writing, in",
        hookSheetChanged: "The file changed since this opened. Here is the current diff: nothing was written.",
        hookSheetNothing: "Nothing to write: the file is already in that state.",
        hookSheetFailed: { "Nothing was written: \($0)" },
        hookCancel: "Cancel",
        hookWrite: "Write",
        system: "System",
        startAtLogin: "Open at login",
        startAtLoginUnavailable: "Unavailable until the app is packaged",
        language: "App language",
        expressions: "Expressions",
        colour: "Colour",
        motion: "Motion",
        editedBadge: "edited",
        resetExpression: "Reset this expression",
        resetBuddy: "Reset the whole buddy",
        export: "Export as .buddy…",
        exported: { "Exported to \($0)" },
        exportFailed: { "Export failed: \($0)" },
        duplicate: "Duplicate",
        newBuddy: "New buddy",
        deleteBuddy: "Delete",
        openBuddyFolder: "Open the folder",
        buddyFolder: "The .buddy files live in the folder below. Edits made here are stored separately and never touch them.",
        inherited: "inherited from the file",
        alertOnFinished: "When a turn ends",
        alertOnFailed: "When a turn fails",
        alertOnNeedsAttention: "When the agent needs an answer",
        voice: "Speak alerts",
        voiceHint: "Loads the speech engine on first use (a few MB).",
        haptics: "Haptic feedback (trackpad)",
        quietWhenFrontmost: "Stay quiet when the terminal is frontmost",
        quietHint: "Notifying about what you are already looking at teaches you to ignore notifications.",
        groupByDirectory: "Group sessions by folder",
        groupByDirectoryHint: "One row per project rather than one per transcript.",
        jumpOnClick: "Clicking a session opens its terminal",
        jumpOnClickHint: "Matched on the tty. Under tmux the app is activated without picking a tab.",
        showUsage: "Show usage in the panel",
        showPillWithoutSession: "Keep the pill visible with no session",
        resetEverything: "Reset every setting",
        resetEverythingHint: "Removes preferences and buddy edits. The .buddy files are left alone.",
        credits: "Credits",
        author: "Author",
        updateCheck: "Check for updates",
        updateCheckHint: "Once a day, from GitHub. Nothing is downloaded.",
        updateGroup: "Update",
        updateUpToDate: "Up to date",
        updateNever: "Never checked",
        updateChecking: "Checking…",
        updateLastCheck: { "Checked \($0) ago" },
        updateAvailable: { "Version \($0) available" },
        updateOpen: "See the release",
        updateCheckNow: "Check now",
        updateHow: "To install: brew upgrade --cask vibebuddy, or the DMG on the page."
    )
}
