import AppKit
import SwiftUI
import VibeBuddyKit

/// A real macOS window, deliberately unlike the notch panel.
///
/// See RFC-010, "Notes d'implémentation".
@MainActor
final class SettingsWindow {

    private var window: NSWindow?
    /// Survives the view, so it can be reset on every `show()`.
    private let navigation = SettingsNavigation()
    private var closeObserver: NSObjectProtocol?
    /// Told when the window opens and closes, so the panel can hold itself open.
    var onVisibilityChange: ((Bool) -> Void)?
    private let l10n: Localisation
    private let appearance: AppearancePrefs
    private let layout: LayoutPrefs
    private let notifications: NotificationPrefs
    private var onLanguageChange: () -> Void
    private var onReset: () -> Void

    init(
        l10n: Localisation,
        appearance: AppearancePrefs,
        layout: LayoutPrefs,
        notifications: NotificationPrefs,
        onLanguageChange: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.l10n = l10n
        self.appearance = appearance
        self.layout = layout
        self.notifications = notifications
        self.onLanguageChange = onLanguageChange
        self.onReset = onReset
    }

    /// Every opening starts on the first pane.
    ///
    /// Reset here rather than in the view: the window is reused, so the view is
    /// only built once and anything it holds persists between visits.
    func show() {
        onVisibilityChange?(true)
        navigation.tab = .general
        if let window {
            bringToFront(window)
            return
        }

        let view = SettingsShell(
            l10n: l10n,
            appearance: appearance,
            layout: layout,
            notifications: notifications,
            onLanguageChange: onLanguageChange,
            onReset: onReset,
            navigation: navigation
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = AppName.display
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onVisibilityChange?(false) }
        }

        bringToFront(window)
    }

    /// Put the window in front **once**, and let it behave like a window after
    /// that.
    ///
    /// It used to be pinned one level above `.statusBar`, so it stayed on top
    /// of every application on the machine — a settings sheet that no other
    /// window could ever cover, and that followed the user into whatever they
    /// switched to. The reason given was that `.floating` (3) sits below the
    /// notch panel (25) and the window would open under the pill that opened
    /// it; the real answer to that is `.normal` plus an activation, which
    /// raises it above ordinary windows without making it a permanent overlay.
    ///
    /// The notch panel does pass over it when deployed. That is correct: the
    /// panel lives in the notch, the settings do not, and the panel must stay
    /// reachable while the settings are open.
    private func bringToFront(_ window: NSWindow) {
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
