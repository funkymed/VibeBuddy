import AppKit
import ServiceManagement
import VibeBuddyKit

/// What macOS has to let this app do, and whether it currently does.
///
/// The app asks for very little on purpose — decision « aucune API Accessibilité
/// en v1 » — and what it does ask for fails **silently** when refused: a jump to
/// the terminal simply does nothing. A user who refused an automation prompt
/// three weeks ago has no way of knowing that is why. This screen is that way.
enum SystemPermissions {

    enum State: Equatable {
        /// Granted, and verified just now rather than remembered.
        case granted
        /// Refused. Only System Settings can undo this — the prompt never
        /// appears twice.
        case denied
        /// Never asked. The prompt appears the first time the app needs it.
        case notAsked
        /// Nothing to grant: the app is not bundled, or the target is not
        /// installed at all.
        case unavailable(reason: String)
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let explanation: String
        let state: State
        /// Where the user goes to change it. Nil when there is nowhere to go.
        let settingsURL: URL?
    }

    /// The bundle identifiers the app drives, and only those.
    ///
    /// `TerminalJumper` speaks to these two and nothing else. Listing a third
    /// here would show a permission the app never uses — which is worse than
    /// showing none, because it invites granting it.
    static let terminals = [
        ("com.googlecode.iterm2", "iTerm2"),
        ("com.apple.Terminal", "Terminal"),
    ]

    static var automationURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    static var loginItemsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    /// Everything worth showing, in the order it matters.
    static func all(l10n: Strings) -> [Item] {
        var items: [Item] = terminals.compactMap { bundleID, name in
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            else { return nil }
            return Item(
                id: bundleID,
                title: l10n.permissionAutomation(name),
                explanation: l10n.permissionAutomationWhy,
                state: automationState(for: bundleID),
                settingsURL: automationURL)
        }

        items.append(Item(
            id: "loginItem",
            title: l10n.permissionLoginItem,
            explanation: l10n.permissionLoginItemWhy,
            state: loginItemState(),
            settingsURL: loginItemsURL))

        return items
    }

    /// Whether this app may drive `bundleID`, **without asking**.
    ///
    /// `askUserIfNeeded: false` is the whole point: a settings screen that
    /// raised a system prompt merely by being opened would train the user to
    /// dismiss prompts. The answer here is a report, never a request.
    static func automationState(for bundleID: String) -> State {
        guard Bundle.main.bundleIdentifier != nil else {
            return .unavailable(reason: "hors bundle")
        }
        var target = AEAddressDesc()
        let identifier = bundleID as NSString
        let data = identifier.utf8String
        let length = strlen(data!)
        guard AECreateDesc(typeApplicationBundleID, data, length, &target) == noErr else {
            return .unavailable(reason: "cible illisible")
        }
        defer { AEDisposeDesc(&target) }

        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(procNotFound): return .unavailable(reason: "application non lancée")
        default: return .notAsked
        }
    }

    /// Not a permission macOS guards, but the same question in the user's mind:
    /// « est-ce que c'est autorisé ? ». Shown beside the real ones rather than
    /// in a second place.
    static func loginItemState() -> State {
        guard Bundle.main.bundleIdentifier != nil else {
            return .unavailable(reason: "hors bundle")
        }
        switch SMAppService.mainApp.status {
        case .enabled: return .granted
        case .requiresApproval: return .denied
        case .notRegistered: return .notAsked
        case .notFound: return .unavailable(reason: "service introuvable")
        @unknown default: return .notAsked
        }
    }
}
