import AppKit
import SwiftUI
import VibeBuddyKit

/// A real macOS window, deliberately unlike the notch panel.
///
/// See RFC-010, "Notes d'implémentation".
@MainActor
final class SettingsWindow {

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    /// Told when the window opens and closes, so the panel can hold itself open.
    var onVisibilityChange: ((Bool) -> Void)?
    private let l10n: Localisation
    private let appearance: AppearancePrefs
    private let layout: LayoutPrefs
    private let notifications: NotificationPrefs
    private var onBuddyChange: (String?) -> Void
    private var onLanguageChange: () -> Void
    private var onReset: () -> Void

    init(
        l10n: Localisation,
        appearance: AppearancePrefs,
        layout: LayoutPrefs,
        notifications: NotificationPrefs,
        onBuddyChange: @escaping (String?) -> Void,
        onLanguageChange: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.l10n = l10n
        self.appearance = appearance
        self.layout = layout
        self.notifications = notifications
        self.onBuddyChange = onBuddyChange
        self.onLanguageChange = onLanguageChange
        self.onReset = onReset
    }

    func show() {
        onVisibilityChange?(true)
        if let window {
            bringToFront(window)
            return
        }

        let view = SettingsShell(
            l10n: l10n,
            appearance: appearance,
            layout: layout,
            notifications: notifications,
            onBuddyChange: onBuddyChange,
            onLanguageChange: onLanguageChange,
            onReset: onReset
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

    /// Put the window in front and keep it there.
    ///
    /// Do not use `.floating` (3): it is below `.statusBar` (25) where the notch
    /// panel lives, so the window opens underneath the pill that opened it.
    private func bringToFront(_ window: NSWindow) {
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
