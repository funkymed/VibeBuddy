import AppKit
import VibeBuddyKit

/// Owns the object graph and the app's relationship with the system.
@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    let wake = WakeCoordinator()
    let animation = AnimationBudget()
    private(set) var geometry: NotchGeometry?
    private var panel: NotchPanel?
    private var sessions: SessionCoordinator?
    /// Held for the life of the app: a `DispatchSourceSignal` that is not retained is
    /// cancelled, and the signal goes back to killing us outright.
    private var terminationSignals: [DispatchSourceSignal] = []
    /// Set by `--simulate-permission <genre>`; nil in normal use.
    static let simulatedPermission: String? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--simulate-permission") else { return nil }
        return index + 1 < args.count ? args[index + 1] : "shell"
    }()
    /// Set by `--simulate-questions [n]`.
    static let simulatedQuestions: Int? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--simulate-questions") else { return nil }
        let next = index + 1 < args.count ? Int(args[index + 1]) : nil
        return max(1, next ?? 3)
    }()
    /// Set by `--simulate-finished`: the end-of-task alert in the pill, which is
    /// objective n°1 of the product and the one thing that cannot be summoned on demand
    /// — it arrives when an agent finishes, not when you are ready to look at it.
    static let simulatesFinished = CommandLine.arguments.contains("--simulate-finished")
    /// The hook socket, and the permission requests it brings in.
    private let hook = HookService()
    let usage = UsageState()
    let l10n = Localisation()
    /// One store, three models: splitting by who observes what keeps a buddy colour
    /// change from invalidating the window layout.
    let prefs: PreferencesStore
    /// Held by value by the settings window, which never rebuilds: a reset reloads these
    /// in place rather than replacing them.
    let appearance: AppearancePrefs
    let layout: LayoutPrefs
    let notifications: NotificationPrefs
    private let voice = VoiceAnnouncer()
    private var settings: SettingsWindow?
    private var buddyWatchers: [ProjectsWatcher] = []
    var onBuddyReload: ((String) -> Void)?

    var showPillOnLaunch = true
    var buddyID: String? = BuiltInBuddy.id

    override init() {
        let prefs = PreferencesStore()
        self.prefs = prefs
        appearance = AppearancePrefs(store: prefs)
        layout = LayoutPrefs(store: prefs)
        notifications = NotificationPrefs(store: prefs)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Before anything reads the support directory.
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
        observeTermination()
        // Before the panel: a hook that connects to nothing exits cleanly, but one that
        // connects to a half-built app is a Claude Code left waiting.
        hook.start()
        hook.watchForExpiry()

        let panel = NotchPanel(wake: wake, budget: animation)
        self.panel = panel
        if showPillOnLaunch { panel.show() }

        let settings = SettingsWindow(
            l10n: l10n,
            appearance: appearance,
            layout: layout,
            notifications: notifications,
            onLanguageChange: { [weak self] in
                guard let self else { return }
                self.panel?.setLanguage(self.l10n.strings, locale: self.l10n.locale)
            },
            onReset: { [weak self] in self?.resetEverything() }
        )
        settings.onVisibilityChange = { [weak self, weak panel] open in
            // Told, but no longer used to close anything: the notch stays usable while
            // the settings are open.
            panel?.settingsAreOpen = open
            // A coalesced write must not be lost when the window closes.
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
            // The preference silences the rendering, never the reading.
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
        // The queue pushes; the panel does not pull.
        hook.permissions.onChange = { [weak self] in
            guard let self else { return }
            self.panel?.setPermission(
                self.hook.permissions.head, waiting: self.hook.permissions.waiting)
        }
        applySimulationFlags(to: panel)

        // The rules live behind the same writer as the hook's own entries (decision
        // D6): one place in this app touches that file.
        let rules = PermissionRules()
        hook.permissions.alwaysAllowed = { rules.granted() }
        panel.onPermissionAlwaysAllowAsked = { model in
            PermissionConsent.make(for: model, rules: rules)
        }
        panel.onConsentConfirmed = { consent in
            do {
                let written = try rules.commit(adding: consent.rule)
                PerfProbe.log.info(
                    "permissions : « \(consent.rule, privacy: .public) » \(written ? "écrite" : "déjà présente", privacy: .public)")
            } catch {
                PerfProbe.log.error(
                    "permissions : écriture impossible — \(String(describing: error), privacy: .public)")
            }
        }

        panel.onPermissionDecision = { [weak self] id, decision in
            guard let self else { return }
            if let decision {
                self.hook.permissions.decide(id, decision)
            } else {
                self.hook.permissions.expire(id)
            }
        }

        sessions.onChange = { [weak self] list in
            guard let self, let panel = self.panel else { return }
            // A transcript that has moved on has overtaken any permission still waiting
            // on it.
            self.hook.expireStale(against: list)
            let live = list.filter(\.isLive)
            // `onThePill`, not `aggregate`: with several sessions the face shows that
            // something is running.
            let activity = SessionDisplayState.onThePill(of: list)?.activity
            panel.setAggregateExpression(Self.forcedFace ?? BuddyExpression.from(
                activity: activity, hasLiveSession: !live.isEmpty, isVisible: true))
            panel.setSessionCount(live.count)
            panel.setSessions(list)
            // D7's preference, applied where liveness is actually known.
            if !self.layout.showPillWithoutSession {
                live.isEmpty ? panel.hide() : panel.show()
            }
        }
        if let face = Self.forcedFace { panel.setAggregateExpression(face) }
        sessions.onChangeLog = { list in
            let live = list.filter(\.isLive).count
            PerfProbe.log.info("sessions: \(live, privacy: .public) live / \(list.count, privacy: .public)")
        }
        sessions.quietWhenTerminalFrontmost = notifications.quietWhenFrontmost
        sessions.start()
        self.sessions = sessions

        // The only unconditional periodic wake in the app, D3.
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

    /// Takes the windows off the screen before dying on `SIGTERM` or `SIGINT`. The
    /// cost, said out loud: an app whose main loop is wedged no longer dies on
    /// `SIGTERM`, because we have just told the kernel to leave it to us.
    private func observeTermination() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.terminateCleanly() }
            }
            source.resume()
            terminationSignals.append(source)
        }
    }

    /// Off the screen first, then the ordinary quit. `terminate` is what runs
    /// `applicationWillTerminate`, and that is where the queue is drained and the socket
    /// unlinked — the things that decide whether a Claude Code somewhere waits out its
    /// 120 s.
    private func terminateCleanly() {
        for window in NSApp.windows { window.orderOut(nil) }
        NSApp.terminate(nil)
    }

    /// The `--simulate-*` flags, in one place.
    private func applySimulationFlags(to panel: NotchPanel) {
        if let kind = Self.simulatedPermission {
            hook.permissions.insertPreview(PermissionSamples.model(kind))
        }
        if let count = Self.simulatedQuestions {
            for model in PermissionSamples.questions(count) {
                hook.permissions.insertPreview(model)
            }
        }
        if Self.simulatesFinished {
            // The pill has to be on screen for an alert to have somewhere to go:
            // `present` refuses from `.hidden`, and « pastille visible sans session »
            // is off by default (D7).
            panel.show()
            // Long enough to be looked at rather than caught.
            panel.present(
                SessionAlert(sessionID: "simulation", projectName: "notch",
                             kind: .finished, at: Date()),
                for: 30)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        wake.suspend()
        // A socket file left behind is one a later `vibe-hook` connects to and waits on
        // — and a hook that waits is a Claude Code that waits.
        hook.stop()
        // The other moment a queued write must not be lost.
        prefs.flush()
    }

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

        // Screen lock is not on NSWorkspace — it only arrives on the distributed
        // centre, undocumented but stable for many releases.
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
    private func watchBuddies() {
        buddyWatchers.forEach { $0.stop() }
        buddyWatchers = []

        let root = BuddyLoader.searchPath
        try? FileManager.default.createDirectory(
            atPath: root, withIntermediateDirectories: true)

        // Resolve symlinks first: a buddy in the search path is usually a link into a
        // working copy, and FSEvents reports writes to the directory holding the real
        // bytes, never to the link's folder.
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

    /// Bring the terminal running `pid` to the front, on the right tab.
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
        // Every buddy now comes from a file.
        var loader = BuddyLoader()
        let loaded = loader.load(id: id)
        panel?.setBuddy(loaded.manifest)
        for problem in loader.problems {
            PerfProbe.log.error("buddy: \(problem, privacy: .public)")
        }
    }

    /// Push the panel-facing preferences.
    private func applyLayoutPrefs() {
        sessions?.quietWhenTerminalFrontmost = notifications.quietWhenFrontmost
        panel?.setLayoutPrefs(
            groupByDirectory: layout.groupByDirectory,
            jumpOnClick: layout.jumpOnClick,
            showUsage: layout.showUsage)
    }

    /// Delete every preference this app owns, then reload from defaults.
    private func resetEverything() {
        for key in PreferencesStore.allKeys { prefs.remove(key) }
        appearance.reload()
        layout.reload()
        notifications.reload()
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

    /// `VIBEBUDDY_FACE=finished` pins the buddy to one expression.
    static let forcedFace: BuddyExpression? = ProcessInfo.processInfo
        .environment["VIBEBUDDY_FACE"]
        .flatMap { BuddyExpression(rawValue: $0.lowercased()) }

}
