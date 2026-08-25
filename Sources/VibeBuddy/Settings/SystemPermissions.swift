import AppKit
import ServiceManagement
import VibeBuddyKit

/// What macOS has to let this app do, and whether it currently does.
enum SystemPermissions {
    enum State: Equatable {
        /// Granted, and verified just now rather than remembered.
        case granted
        /// Refused.
        case denied
        /// Never asked.
        case notAsked
        /// Nothing to grant: the app is not bundled, or the target is not installed at
        /// all.
        case unavailable(reason: String)
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let explanation: String
        let state: State
        /// Where the user goes to change it.
        let settingsURL: URL?
    }

    /// The bundle identifiers the app drives, and only those.
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

    /// Whether this app may drive `bundleID`, without asking.
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
