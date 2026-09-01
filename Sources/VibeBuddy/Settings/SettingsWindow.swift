import AppKit
import SwiftUI
import VibeBuddyKit

/// A real macOS window, deliberately unlike the notch panel.
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
    private let updates: UpdateState
    private var onLanguageChange: () -> Void
    private var onReset: () -> Void

    init(
        l10n: Localisation,
        appearance: AppearancePrefs,
        layout: LayoutPrefs,
        notifications: NotificationPrefs,
        updates: UpdateState,
        onLanguageChange: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.l10n = l10n
        self.appearance = appearance
        self.layout = layout
        self.notifications = notifications
        self.updates = updates
        self.onLanguageChange = onLanguageChange
        self.onReset = onReset
    }

    /// Every opening starts on the first pane.
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
            updates: updates,
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

    /// Put the window in front once, and let it behave like a window after that.
    private func bringToFront(_ window: NSWindow) {
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
