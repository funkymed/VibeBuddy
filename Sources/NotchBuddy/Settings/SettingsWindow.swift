import AppKit
import SwiftUI
import NotchBuddyKit

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
    private var onBuddyChange: (String?) -> Void
    private var onLanguageChange: () -> Void

    init(
        l10n: Localisation,
        onBuddyChange: @escaping (String?) -> Void,
        onLanguageChange: @escaping () -> Void
    ) {
        self.l10n = l10n
        self.onBuddyChange = onBuddyChange
        self.onLanguageChange = onLanguageChange
    }

    func show() {
        onVisibilityChange?(true)
        if let window {
            bringToFront(window)
            return
        }

        let view = SettingsView(
            l10n: l10n,
            onBuddyChange: onBuddyChange,
            onLanguageChange: onLanguageChange
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "notch-buddy"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 360))
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

private struct SettingsView: View {
    @Bindable var l10n: Localisation
    var onBuddyChange: (String?) -> Void
    var onLanguageChange: () -> Void

    @AppStorage("notchbuddy.buddy") private var buddyID: String = "emoji"
    @State private var available: [BuddyManifest] = BuddyLoader.available()

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { l10n.language },
                    set: { l10n.set($0); onLanguageChange() }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    Text(l10n.strings.settingsLanguage)
                }
                // What `.system` means today, so the choice is not a guess.
                if l10n.language == .system {
                    Text(l10n.strings.settingsLanguageSystem(l10n.effective.displayName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker(selection: Binding(
                    get: { buddyID },
                    set: { buddyID = $0; onBuddyChange($0) }
                )) {
                    ForEach(available, id: \.id) { manifest in
                        Text("\(manifest.name)  \(manifest.expressions["idle"]?.frames.first ?? "")")
                            .tag(manifest.id)
                    }
                } label: {
                    Text(l10n.strings.settingsBuddy)
                }
                // Live preview: the first frame of each expression, in its own
                // colour. Choosing a buddy from a name alone is a guess.
                if let manifest = available.first(where: { $0.id == buddyID }) {
                    HStack(spacing: 14) {
                        ForEach(BuddyExpression.allCases, id: \.self) { expression in
                            if let e = manifest.expression(expression) {
                                Text(e.frames.first ?? "")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: e.colour ?? manifest.colour) ?? .primary)
                            }
                        }
                    }
                    .lineLimit(1)
                    .padding(.vertical, 2)
                }

                HStack {
                    Spacer()
                    // No reload button: buddy files are watched and reloaded as
                    // they are saved. A button offering to do what already
                    // happens teaches people to distrust the automatic path.
                    Button(l10n.strings.settingsOpenFolder) {
                        let path = BuddyLoader.searchPath
                        try? FileManager.default.createDirectory(
                            atPath: path, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 300)
    }
}
