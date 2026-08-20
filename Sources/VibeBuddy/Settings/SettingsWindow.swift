import AppKit
import SwiftUI
import VibeBuddyKit

/// A real macOS window, deliberately unlike the notch panel.
///
/// RFC-010 settled this: settings do **not** live in the pill. The panel folds
/// away the moment the cursor leaves it, and a settings surface that vanishes
/// while you reach for your mouse is hostile. Settings are browsed, compared and
/// revisited — they want a window you can resize and leave open.
///
/// It also **can** become key, unlike `NotchPanel`, so text fields and keyboard
/// navigation work here. That is the other half of the reason to separate them.
///
/// The app is an accessory with no menu bar, so `⌘,` reaches nothing. The only
/// way in is the gear in the panel header.
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
        // Resizable now: a sidebar plus a buddy editor does not fit a fixed
        // 520x360, and the sections differ enough in height that a single size
        // would be wrong for most of them.
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
    /// An `.accessory` app has no Dock icon and cannot be raised the usual way,
    /// so activating explicitly is what stops the window opening *behind*
    /// whatever the user was looking at.
    ///
    /// **The level has to clear the pill, not merely float.** `.floating` is 3
    /// and `.statusBar` — where the notch panel lives — is 25, so a "floating"
    /// settings window opens *underneath* the very pill that opened it. One
    /// above the panel is the only value that works.
    private func bringToFront(_ window: NSWindow) {
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
