import Foundation

/// The settings window's own catalogue.
///
/// Apart from `Strings` because the surfaces differ in lifetime. Same rule: a
/// `struct`, so a string added without a translation does not compile.
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

    // General
    public let system: String
    public let startAtLogin: String
    public let startAtLoginUnavailable: String
    public let language: String

    // Buddy
    public let activeBuddy: String
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
    public let openBuddyFolder: String

    // About
    public let credits: String
    public let creditsBody: String
    public let author: String

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
        system: "Système",
        startAtLogin: "Ouvrir à l'ouverture de session",
        startAtLoginUnavailable: "Indisponible tant que l'app n'est pas empaquetée (RFC-011)",
        language: "Langue de l'app",
        activeBuddy: "Buddy actif",
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
        openBuddyFolder: "Ouvrir le dossier",
        credits: "Crédits",
        creditsBody: "Inspired by Notch-Pilot & VibeIsland",
        author: "Auteur"
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
        system: "System",
        startAtLogin: "Open at login",
        startAtLoginUnavailable: "Unavailable until the app is packaged (RFC-011)",
        language: "App language",
        activeBuddy: "Active buddy",
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
        openBuddyFolder: "Open the folder",
        credits: "Credits",
        creditsBody: "Inspired by Notch-Pilot & VibeIsland",
        author: "Author"
    )
}
