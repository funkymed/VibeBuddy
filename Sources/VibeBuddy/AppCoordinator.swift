import AppKit
import VibeBuddyKit

/// Owns the object graph and the app's relationship with the system.
///
/// The reference implementation injects nine objects straight into a single
/// SwiftUI view (`AppDelegate.swift:5-15`), which is the root cause of its
/// 3 738-line view file. Here the coordinator holds the graph and hands out
/// only what each layer needs.
///
/// Its second job is the one the reference never does at all: **stopping**.
/// Nothing in that codebase ever calls `stop()`, so its timers keep firing with
/// the lid shut. Sleep and screen lock suspend the wake coordinator here, which
/// tears the shared timer down to zero.
@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {

    let wake = WakeCoordinator()
    let animation = AnimationBudget()
    private(set) var geometry: NotchGeometry?
    private var panel: NotchPanel?
    private var sessions: SessionCoordinator?
    let usage = UsageState()
    let l10n = Localisation()
    /// One store, three models — RFC-010. Splitting by *who observes what* is
    /// what stops a buddy colour change from invalidating the window layout.
    let prefs = PreferencesStore()
    private(set) lazy var appearance = AppearancePrefs(store: prefs)
    private(set) lazy var layout = LayoutPrefs(store: prefs)
    private(set) lazy var notifications = NotificationPrefs(store: prefs)
    private let voice = VoiceAnnouncer()
    private var settings: SettingsWindow?
    private var buddyWatchers: [ProjectsWatcher] = []
    /// Fired on every hot reload. Used by the bench to prove it happens.
    var onBuddyReload: ((String) -> Void)?

    /// Until RFC-003 drives visibility from live sessions, the pill is shown on
    /// launch so RFC-002 can be exercised at all.
    var showPillOnLaunch = true
    /// Which buddy to load. Nil means the built-in one.
    var buddyID: String? = "emoji"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Before anything reads the support directory: the buddies in there are
        // usually symbolic links into a working copy, and an app that silently
        // stops seeing them has lost them as far as the user is concerned.
        switch SupportDirectory.migrate() {
        case .notNeeded: break
        case let .moved(from):
            PerfProbe.log.info("dossier de support déplacé depuis \(from, privacy: .public)")
        case let .bothPresent(legacy):
            PerfProbe.log.error("deux dossiers de support, l'ancien est ignoré : \(legacy, privacy: .public)")
        case let .failed(reason):
            PerfProbe.log.error("migration du dossier de support impossible : \(reason, privacy: .public)")
        }
        geometry = NotchGeometry.resolve()
        observeSystemState()

        let panel = NotchPanel(wake: wake, budget: animation)
        self.panel = panel
        if showPillOnLaunch { panel.show() }

        let settings = SettingsWindow(
            l10n: l10n,
            appearance: appearance,
            layout: layout,
            notifications: notifications,
            onBuddyChange: { [weak self] id in self?.loadBuddy(id) },
            onLanguageChange: { [weak self] in
                guard let self else { return }
                self.panel?.setLanguage(self.l10n.strings, locale: self.l10n.locale)
            },
            onReset: { [weak self] in self?.resetEverything() }
        )
        settings.onVisibilityChange = { [weak self, weak panel] open in
            panel?.suppressesHover = open
            // Closing the window is one of the two moments where waiting a
            // quarter second for a coalesced write is a real risk.
            if !open {
                self?.prefs.flush()
                self?.applyLayoutPrefs()
                self?.loadBuddy(self?.appearance.buddyID)
            }
        }
        self.settings = settings
        panel.onSettings = { settings.show() }
        panel.onJump = { [weak self] pid in self?.jump(to: pid) }

        panel.setLanguage(l10n.strings, locale: l10n.locale)
        PerfProbe.log.info("langue : \(self.l10n.effective.rawValue, privacy: .public)")

        panel.onPanelVisibilityChange = { [weak self] open in
            guard let self else { return }
            usage.isPanelOpen = open
            if open { Task { @MainActor in
                await self.usage.refresh()
                self.panel?.setUsage(self.usage.status)
            } }
        }

        applyLayoutPrefs()
        loadBuddy(appearance.buddyID)
        watchBuddies()

        let sessions = SessionCoordinator(wake: wake)
        sessions.onAlert = { [weak self] alert in
            guard let self else { return }
            // The preference silences the *rendering*, never the reading: the
            // state machine has already decided what happened, and a setting
            // that changed that would make the panel and the alerts disagree.
            guard self.notifications.allows(alert.kind) else {
                PerfProbe.log.info("alerte tue par préférence: \(alert.kind.rawValue, privacy: .public)")
                return
            }
            PerfProbe.log.info(
                "alerte: \(alert.projectName, privacy: .public) \(alert.kind.rawValue, privacy: .public)")
            self.panel?.present(alert)
            if self.notifications.haptics { Haptics.tap() }
            if self.notifications.voice {
                let label = NotchShellView.label(for: alert.kind, l10n: self.l10n.strings)
                self.voice.announce(
                    "\(alert.projectName) \(label)", locale: self.l10n.locale)
            }
        }
        sessions.onChange = { [weak self] list in
            guard let self, let panel = self.panel else { return }
            let live = list.filter(\.isLive)
            // A pending question outranks everything: it is the one state where
            // nothing moves until the user acts.
            let activity: SessionActivity? = live.contains(where: \.awaitingAnswer) ? .awaiting
                : (live.contains { $0.action != .none } ? .working
                : (live.contains { $0.turnEnded } ? .finished : (live.isEmpty ? nil : .idle)))
            panel.setExpression(BuddyExpression.from(
                activity: activity, hasLiveSession: !live.isEmpty, isVisible: true))
            panel.setSessionCount(live.count)
            panel.setSessions(list)
            // D7's preference, applied where liveness is actually known.
            if !self.layout.showPillWithoutSession {
                live.isEmpty ? panel.hide() : panel.show()
            }
        }
        sessions.onChangeLog = { list in
            let live = list.filter(\.isLive).count
            PerfProbe.log.info("sessions: \(live, privacy: .public) live / \(list.count, privacy: .public)")
        }
        sessions.quietWhenTerminalFrontmost = notifications.quietWhenFrontmost
        sessions.start()
        self.sessions = sessions

        // The only unconditional periodic wake in the app — RFC-001, D3. The
        // coordinator ticks at `.lazy`; `UsageState` decides from there whether
        // enough time has passed, so the cadence adapts without a second timer.
        wake.register(id: "usage", cadence: .lazy) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.usage.refresh()
                self.panel?.setUsage(self.usage.status)
            }
        }
        Task { @MainActor in
            await usage.refresh()
            panel.setUsage(usage.status)
        }

        PerfProbe.log.info("launched · notch=\(self.geometry?.hasNotch ?? false, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        wake.suspend()
        // The other moment a queued write must not be lost.
        prefs.flush()
    }

    // MARK: - System state

    private func observeSystemState() {
        let workspace = NSWorkspace.shared.notificationCenter

        workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enterLowPower("sleep") }
        }

        workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.leaveLowPower("wake") }
        }

        // Screen lock is not on NSWorkspace — it only arrives on the
        // distributed centre, undocumented but stable for many releases.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enterLowPower("lock") }
        }
        distributed.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.leaveLowPower("unlock") }
        }

        // Screen layout changes invalidate the resolved notch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let resolved = NotchGeometry.resolve(preferredScreenID: self.geometry?.screenID)
                guard resolved != self.geometry else { return }
                self.geometry = resolved
                self.panel?.refreshGeometry()
                PerfProbe.log.info("screen layout changed")
            }
        }
    }

    /// Reload the active buddy whenever its folder changes.
    ///
    /// A `.buddy` file is something a person edits by hand, in a text editor,
    /// while watching the notch. Without this the loop is "edit, quit, relaunch"
    /// — and worse, the obvious guess is that recompiling would help, which it
    /// never does: the files live outside the binary entirely.
    ///
    /// Reuses `ProjectsWatcher` rather than adding a second FSEvents
    /// implementation; it was written for transcripts but knows nothing about
    /// them.
    private func watchBuddies() {
        buddyWatchers.forEach { $0.stop() }
        buddyWatchers = []

        let root = BuddyLoader.searchPath
        try? FileManager.default.createDirectory(
            atPath: root, withIntermediateDirectories: true)

        // Watch where the files *really* are, not only where they appear.
        //
        // A buddy in the search path is often a symlink into a working copy —
        // that is how anyone edits one seriously. FSEvents reports writes to the
        // directory holding the actual bytes, so watching the link's folder sees
        // nothing at all when the target changes. Resolving first is the whole
        // difference between hot reload working and appearing to work.
        var directories = Set([root])
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
            for entry in entries where entry.hasSuffix(".buddy") {
                let resolved = URL(fileURLWithPath: "\(root)/\(entry)").resolvingSymlinksInPath()
                directories.insert(resolved.deletingLastPathComponent().path)
            }
        }

        for directory in directories {
            let watcher = ProjectsWatcher { [weak self] changed in
                guard changed.contains(where: { $0.hasSuffix(".buddy") }) else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.loadBuddy(self.appearance.buddyID)
                    PerfProbe.log.info("buddy rechargé")
                    self.onBuddyReload?(self.panel?.currentBuddyID ?? "?")
                }
            }
            watcher.start(path: directory)
            buddyWatchers.append(watcher)
        }
    }

    /// Load a buddy by id, falling back to the built-in one.
    ///
    /// Swapping is just a redraw: the renderer holds no state, so there is
    /// nothing to tear down between manifests.
    /// Bring the terminal running `pid` to the front, on the right tab.
    ///
    /// Off the main actor because an Apple Event is a round trip to another
    /// process: on the main thread it would freeze the panel for as long as
    /// iTerm2 takes to answer, and the panel is under the cursor at that exact
    /// moment. `TerminalJumper` is a pure function of the pid, so nothing here
    /// needs isolation.
    ///
    /// The message clears itself. A note that stayed would still be on screen
    /// the next time the panel opened, describing something that happened
    /// minutes ago.
    private func jump(to pid: pid_t) {
        let strings = l10n.strings
        Task.detached(priority: .userInitiated) {
            let outcome = TerminalJumper.jump(agentPID: pid)
            let note: String? = switch outcome {
            case .selectedTab: nil
            case .activatedApp: strings.jumpNoTab
            case .noTerminal: strings.jumpNoTerminal
            case let .failed(message): strings.jumpFailed(message)
            }
            await MainActor.run { self.panel?.setJumpNote(note) }
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            await MainActor.run { self.panel?.setJumpNote(nil) }
        }
    }

    private func loadBuddy(_ id: String?) {
        // A buddy created in the editor has no file, so the loader cannot find
        // it — the layer holds it whole. Either way the overrides are applied
        // afterwards, in the one place that knows the precedence.
        if let id, let created = appearance.overrides.manifest(forCreated: id) {
            panel?.setBuddy(appearance.resolved(created))
            panel?.setPixelSize(appearance.pixelSize)
            return
        }
        var loader = BuddyLoader()
        let loaded = loader.load(id: id)
        panel?.setBuddy(appearance.resolved(loaded.manifest))
        panel?.setPixelSize(appearance.pixelSize)
        for problem in loader.problems {
            PerfProbe.log.error("buddy: \(problem, privacy: .public)")
        }
    }

    /// Push the panel-facing preferences. Called at launch and whenever the
    /// settings window closes, which is when they can have changed.
    private func applyLayoutPrefs() {
        sessions?.quietWhenTerminalFrontmost = notifications.quietWhenFrontmost
        panel?.setLayoutPrefs(
            groupByDirectory: layout.groupByDirectory,
            jumpOnClick: layout.jumpOnClick,
            showUsage: layout.showUsage)
    }

    /// Delete every preference this app owns, then reload from defaults.
    ///
    /// Keys are removed one by one rather than by wiping the domain: the domain
    /// also holds system-managed entries for this bundle, and taking those with
    /// it would be a bug that only shows up much later.
    private func resetEverything() {
        for key in PreferencesStore.allKeys { prefs.remove(key) }
        appearance = AppearancePrefs(store: prefs)
        layout = LayoutPrefs(store: prefs)
        notifications = NotificationPrefs(store: prefs)
        applyLayoutPrefs()
        loadBuddy(appearance.buddyID)
        PerfProbe.log.info("réglages réinitialisés")
    }

    private func enterLowPower(_ reason: String) {
        wake.suspend()
        animation.set(.still)
        panel?.hide()
        sessions?.stop()
        buddyWatchers.forEach { $0.stop() }
        buddyWatchers = []
        PerfProbe.log.info("suspended (\(reason, privacy: .public))")
    }

    private func leaveLowPower(_ reason: String) {
        wake.resume()
        if showPillOnLaunch { panel?.show() }
        sessions?.start()
        watchBuddies()
        PerfProbe.log.info("resumed (\(reason, privacy: .public))")
    }
}
