import AppKit
import SwiftUI
import VibeBuddyKit
import VibeHookProtocol

/// The window.
@MainActor
final class NotchPanel: NSPanel {
    /// The largest the panel gets: the sessions view is written to this, and a
    /// permission never grows past it — the text was already cut at parse time, but a
    /// diff of forty lines would still ask for a window taller than the screen.
    static let panelMaxSize = CGSize(width: 560, height: 460)
    /// The smallest.
    static let panelMinHeight: CGFloat = 200
    /// Kept at panel width even in pill state, so the transition never jumps
    /// horizontally.
    static let carrierWidth: CGFloat = 560

    /// What the panel is actually sized to right now.
    var panelSize: CGSize {
        guard let measured = measuredPanelHeight else { return Self.panelMaxSize }
        return CGSize(
            width: Self.panelMaxSize.width,
            height: min(max(measured, Self.panelMinHeight), Self.panelMaxSize.height))
    }

    /// The height the permission panel asked for, or nil when the panel is not showing
    /// one.
    private var measuredPanelHeight: CGFloat?

    private typealias Host = ClickThroughHostView<NotchShellView>

    private let wake: WakeCoordinator
    private let budget: AnimationBudget
    private let hover: HoverProbe
    /// Do not erase to `AnyView`: it boxes on every rebuild and destroys the structural
    /// comparison SwiftUI uses to skip untouched subtrees.
    private var host: Host!
    private let snapPreview = SnapPreviewPanel()
    private let metrics = PanelMetrics()
    private var currentAlert: SessionAlert?
    private var buddy: BuddyManifest?
    /// Where the pointer is, and what the face makes of it.
    let gaze = PointerGaze()
    private lazy var pointer = PointerMonitor(gaze: gaze)
    private var expression: BuddyExpression = .sleeping
    private var sessionCount = 0
    private var sessions: [AgentSession] = []
    private var contentRevealed = false
    private var revealWork: DispatchWorkItem?
    var onQuit: () -> Void = { NSApp.terminate(nil) }
    var onSettings: () -> Void = {}
    /// Clicking a live session row.
    var onJump: (pid_t) -> Void = { _ in }
    /// Taking a session off the list. Nil hides the control.
    var onDismissSession: ((AgentSession) -> Void)?
    var onRestoreDismissed: (() -> Void)?
    /// How many rows are hidden, so the panel can offer the way back.
    var dismissedCount = 0 {
        didSet { if dismissedCount != oldValue, state == .panel { rebuildContent() } }
    }
    private var jumpNote: String?
    /// Which request is on screen, which consent is pending, and in what order the two
    /// get answered and written.
    private let permissions = PermissionRouter()
    /// Owned here so it survives the view rebuilds: a loader recreated per rebuild has
    /// an empty cache, which is the defect this task exists to remove.
    private let timelines = SessionTimelineLoader()

    /// Kept on the panel so its owner never learns about the router: the coordinator
    /// sets these on the window it built.
    var onPermissionDecision: ((String, HookDecision?) -> Void)? {
        get { permissions.onDecision }
        set { permissions.onDecision = newValue }
    }
    var onPermissionAlwaysAllowAsked: ((PermissionRequestModel) -> PermissionConsent?)? {
        get { permissions.onAlwaysAllowAsked }
        set { permissions.onAlwaysAllowAsked = newValue }
    }
    var onConsentConfirmed: ((PermissionConsent) -> Void)? {
        get { permissions.onConsentConfirmed }
        set { permissions.onConsentConfirmed = newValue }
    }
    /// Panel-facing preferences, held as plain values: observing the models would
    /// re-evaluate the view on every preference write.
    private var groupByDirectory = true
    private var jumpOnClick = true
    private var showUsage = true

    /// Suppresses hover while another surface of ours owns the screen.
    private var opening = false

    /// Whether the settings window is on screen.
    var settingsAreOpen = false
    private var usage: UsageState.Status = .unknown
    private var l10n: Strings = .french
    private var locale: Locale = .current
    private var alertDismissal: DispatchWorkItem?

    private(set) var geometry: NotchGeometry?
    private var anchorFraction: CGFloat = 0.5

    /// State, re-entry guard and frame generation live in the Kit, where they are
    /// testable without a window.
    private let machine = PanelStateMachine()

    var state: PanelState { machine.state }

    private func setState(_ next: PanelState) { machine.move(to: next) }

    private static let expandCurve = CAMediaTimingFunction(name: .easeOut)

    private static let dragThreshold: CGFloat = 5
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var dragTravel: CGFloat = 0
    private var isDragging = false
    /// Do not drop this guard: `hitTest` returning nil still delivers the event to the
    /// *window*, so a menu-bar click through a margin also drags the pill.
    private var dragArmed = false

    init(wake: WakeCoordinator, budget: AnimationBudget) {
        self.wake = wake
        self.budget = budget
        self.hover = HoverProbe(wake: wake)

        super.init(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 300, height: 32)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Dark, whatever the system is set to.
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isMovable = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        alphaValue = 0

        host = Host(rootView: shellView)
        contentView = host

        // The poll below is the safety net: a pointer warped by a hotkey emits no enter
        // event at all.
        host.onHoverChange = { [weak self] hovering in
            guard let self else { return }
            self.logHover(source: "zone", hovering: hovering)
            if !hovering { self.dismissedAnAsk = false }
            if let next = PanelStateMachine.nextState(
                from: self.state, hovering: hovering,
                opening: self.opening, holdingAnAsk: self.isHoldingAnAsk,
                dismissedAnAsk: self.dismissedAnAsk) {
                self.setState(next)
            }
        }

        hover.onChange = { [weak self] hovering in
            guard let self else { return }
            self.logHover(source: "sonde", hovering: hovering)
            if !hovering { self.dismissedAnAsk = false }
            if let next = PanelStateMachine.nextState(
                from: self.state, hovering: hovering,
                opening: self.opening, holdingAnAsk: self.isHoldingAnAsk,
                dismissedAnAsk: self.dismissedAnAsk) {
                self.setState(next)
            }
        }

        machine.onApply = { [weak self] pass in self?.applyEffects(pass) }
        pointer.onSample = { [weak self] in self?.pointerDidSample() }

        refreshGeometry()
        rebuildContent()
    }

    /// Set when an ask closes the panel, cleared when the pointer leaves. See
    /// `PanelStateMachine.nextState`.
    private var dismissedAnAsk = false
    /// Lowers the frame rate again once a chase has run its course.
    private var chaseWindDown: DispatchWorkItem?

    /// Whether the panel is holding something that waits on a person.
    private var isHoldingAnAsk: Bool { permissions.isHoldingAnAsk }

    /// Key while the panel is open, never while it is a pill.
    override var canBecomeKey: Bool { state == .panel }
    override var canBecomeMain: Bool { false }

    func show() {
        guard state == .hidden else { return }
        setState(.pill)
    }

    func hide() {
        guard state != .hidden else { return }
        setState(.hidden)
    }

    /// Size of the drawn pill, from the same `PillLayout` the content uses.
    var pillSize: CGSize {
        guard let geometry else { return CGSize(width: 300, height: 32) }
        let alertText = (state == .speech ? currentAlert : nil).map {
            "\($0.projectName) \(NotchShellView.label(for: $0.kind, l10n: l10n))"
        }
        let layout = PillLayout.resolve(
            geometry: geometry, buddy: buddy,
            sessionCount: sessionCount, alertText: alertText)
        return CGSize(width: layout.totalWidth, height: layout.height)
    }

    /// The region that absorbs clicks and arms the hover, per state.
    private func hitRegion(for state: PanelState) -> Host.HitRegion {
        switch state {
        case .hidden: return .none
        case .panel: return .full
        case .pill, .speech: return .strip(width: pillSize.width, offsetX: 0)
        }
    }

    private func targetFrame(for state: PanelState) -> CGRect? {
        let size = state == .panel ? panelSize : pillSize
        let carrier = CGSize(width: Self.carrierWidth, height: size.height)
        return geometry.map {
            NotchFrameSolver.frame(size: carrier, geometry: $0, fraction: anchorFraction)
        }
    }

    /// Do not use `setFrame(_:display:animate:false)` here: an in-flight `animator()`
    /// keeps driving the window and it lands at the old target.
    private func setFrameImmediately(_ target: CGRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            animator().setFrame(target, display: true)
        }
    }

    /// Takes the key status on the next run-loop turn, if the panel still wants it by
    /// then.
    private func scheduleKeyIfDeployed() {
        guard !keyRequestPending else { return }
        keyRequestPending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.keyRequestPending = false
                guard self.state == .panel, !self.settingsAreOpen,
                      self.isVisible, !self.isKeyWindow
                else { return }
                self.makeKey()
            }
        }
    }

    private var keyRequestPending = false

    /// Everything a state change does to the window.
    private func applyEffects(_ pass: PanelStateMachine.Pass) {
        let state = pass.state
        let animated = pass.animated
        let generation = pass.generation
        let size = state == .panel ? panelSize : pillSize
        let carrier = CGSize(width: Self.carrierWidth, height: size.height)

        // Destination region up front: interpolating it drops the pointer out of the
        // growing panel and collapses it mid-open.
        host.hitRegion = hitRegion(for: state)
        // The probe needs the same treatment, and did not have it: its rect was only
        // reassigned once the animation had finished, so for the whole growth it
        // compared the pointer against the 38 pt pill.
        hover.pillRect = hoverRect(for: state)
        opening = state == .panel

        // Unfused mouse movement while the panel is open.
        NSEvent.isMouseCoalescingEnabled = (state != .panel)

        if state.isVisible { orderFrontRegardless() }
        // Key only while deployed, and only so the cursor can be ours.
        scheduleKeyIfDeployed()

        // Closing the panel ends the question, so the face goes back to speaking for
        // everything rather than for one session.
        if state != .panel { clearSelection() }

        revealWork?.cancel()
        if state == .panel {
            contentRevealed = false
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.state == .panel else { return }
                    self.contentRevealed = true
                    self.rebuildContent()
                }
            }
            revealWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + PanelTiming.expand * PanelTiming.contentRevealFraction,
                execute: work)
        } else {
            contentRevealed = false
        }

        // Content swaps before the frame moves, so the shape morphs with it.
        rebuildContent()

        let target = targetFrame(for: state)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Never skip the frame change on `frame.size == carrier`: mid-animation the
        // window passes through the target size, and a collapse taking that shortcut
        // left it at 460 pt while the state said pill — a 38 pt hover strip became a
        // 460 pt column.
        guard animated, !reduceMotion, state != .hidden else {
            if let target { setFrameImmediately(target) }
            metrics.drawnWidth = size.width
            alphaValue = state.isVisible ? 1 : 0
            if !state.isVisible { orderOut(nil) }
            finishStateChange(generation: generation)
            return
        }

        growTogether(
            to: target,
            drawnWidth: size.width,
            growing: carrier.height > frame.height,
            generation: generation
        )
    }

    /// Width animates in SwiftUI, height on the `NSWindow`: same duration, same curve,
    /// same run-loop turn, or the shape stretches before it settles.
    private func growTogether(
        to target: CGRect?, drawnWidth: CGFloat, growing: Bool, generation: Int
    ) {
        let duration = growing ? PanelTiming.expand : PanelTiming.collapse

        // Nothing to grow from on the very first appearance.
        if metrics.drawnWidth == 0 {
            metrics.drawnWidth = drawnWidth
        } else {
            withAnimation(.easeOut(duration: duration)) {
                metrics.drawnWidth = drawnWidth
            }
        }
        alphaValue = 1

        guard let target else { finishStateChange(generation: generation); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = Self.expandCurve
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishStateChange(generation: generation) }
        }
    }

    /// Told when the panel opens, so usage can be polled more tightly.
    var onPanelVisibilityChange: ((Bool) -> Void)?

    private func finishStateChange(generation: Int? = nil) {
        // A superseded animation's completion describes a frame already left.
        guard machine.isCurrent(generation) else { return }

        // Last line of defence: both hover regions are read from the frame.
        if state != .hidden, let target = targetFrame(for: state), frame != target {
            setFrameImmediately(target)
        }

        // Re-assert on the settled frame: `applyEffects` set it before the resize.
        host.hitRegion = hitRegion(for: state)
        host.refreshTrackingNow()

        opening = false

        // The panel is open and the animation is over, so whatever became of the reveal
        // work item, the content belongs on screen now.
        if state == .panel, !contentRevealed {
            revealWork?.cancel()
            contentRevealed = true
            rebuildContent()
        }

        onPanelVisibilityChange?(state == .panel)
        updateGaze()
        hover.pillRect = pillScreenRect
        hover.setActive(state.isVisible)
        refreshAnimationBudget()
    }
    /// Hover opens the panel from `.pill` and from `.speech`.

    /// `log stream --predicate 'subsystem == "com.vibebuddy"' --info`
    private func logHover(source: String, hovering: Bool) {
        let mouse = NSEvent.mouseLocation
        let polled = hover.pillRect
        let tracking = host.absorbingRect
        let line = String(
            format: "hover %@ %@ état=%@ souris=(%.0f,%.0f) sondé=[%.0f…%.0f × %.0f…%.0f] suivi=%.0f×%.0f fenêtre=[%.0f…%.0f × %.0f…%.0f]",
            source, hovering ? "entrée" : "sortie", String(describing: state),
            mouse.x, mouse.y,
            polled.minX, polled.maxX, polled.minY, polled.maxY,
            tracking.width, tracking.height,
            frame.minX, frame.maxX, frame.minY, frame.maxY)
        PerfProbe.log.info("\(line, privacy: .public)")
    }

    /// The three rects that decide when the panel opens, for `--hover`.
    var debugTrackingRect: CGRect { host.absorbingRect }
    /// What the view really paints, scanned from its own bitmap.
    var debugPaintedRect: CGRect { HoverDiagnostics.paintedRect(of: host) }
    var debugPolledRect: CGRect { hover.pillRect }
    func debugSetState(_ next: PanelState) { setState(next) }
    var debugState: String { String(describing: state) }

    /// Screen-space rect of the visible pill, which is narrower than the window.
    private func hoverRect(for state: PanelState) -> CGRect {
        guard let target = targetFrame(for: state) else { return pillScreenRect }
        let width = state == .panel ? panelSize.width : pillSize.width
        return CGRect(
            x: target.midX - width / 2, y: target.minY,
            width: width, height: target.height)
    }

    private var pillScreenRect: CGRect {
        let f = frame
        let w = state == .panel ? panelSize.width : pillSize.width
        return CGRect(x: f.midX - w / 2, y: f.minY, width: w, height: f.height)
    }

    /// One construction site, used by the initialiser and by every rebuild.
    private var shellView: NotchShellView {
        NotchShellView(state: state, geometry: geometry, budget: budget, metrics: metrics,
                       alert: currentAlert, buddy: buddy, expression: expression,
                       sessionCount: sessionCount, sessions: sessions,
                       showPanelContent: contentRevealed, usage: usage,
                       l10n: l10n, locale: locale,
                       onSettings: onSettings, onQuit: onQuit,
                       onJump: onJump, onSelect: { [weak self] in self?.select($0) },
                       onDismissSession: onDismissSession,
                       dismissedCount: dismissedCount,
                       onRestoreDismissed: onRestoreDismissed,
                       jumpNote: jumpNote, timelines: timelines,
                       gaze: gaze,
                       permission: permissions.permission,
                       permissionWaiting: permissions.waiting,
                       onPermissionDeny: { [weak self] in self?.answerPermission(.deny(message: self?.l10n.permissionDenied ?? "")) },
                       onPermissionAllow: { [weak self] in self?.answerPermission(.allow) },
                       onPermissionAlwaysAllow: { [weak self] in self?.alwaysAllowPermission() },
                       onPermissionAnswer: { [weak self] in self?.answerPermission(QuestionAnswer.decision(for: $0)) },
                       consent: permissions.consent,
                       onConsentCancel: { [weak self] in self?.cancelConsent() },
                       onConsentConfirm: { [weak self] in self?.confirmConsent() },
                       groupByDirectory: groupByDirectory,
                       jumpOnClick: jumpOnClick, showUsage: showUsage,
                       panelHeight: state == .panel ? panelSize.height : 0)
    }

    private func rebuildContent() {
        host.hosting.rootView = shellView
    }

    /// Shows a request, or takes the last one away.
    func setPermission(_ model: PermissionRequestModel?, waiting: Int) {
        let verdict = permissions.set(model, waiting: waiting)
        // Nothing changed: not even a remeasure, or the same request would pay for an
        // off-screen layout and an animation on every repeat.
        guard verdict.changed else { return }

        // Measured once everything the panel shows has settled, and
        // unconditionally.
        measuredPanelHeight = measurePermissionHeight()

        if verdict.hasRequest {
            if state != .panel {
                setState(.panel)
            } else {
                // Already open on another request.
                rebuildContent()
                resizeToContent(animated: true)
            }
        } else if verdict.wasShowingSomething {
            // The pointer is on the button that was just clicked, so without this the
            // hover reopens the panel on the sessions list a frame later.
            dismissedAnAsk = true
            setState(.pill)
        } else {
            rebuildContent()
        }

        // The face was pinned to `idle` while the ask was up; put back whatever the
        // sessions are actually doing now that it is gone.
        applyExpression()
    }

    /// Measures what the permission panel wants, and moves the window to it.
    private func refreshPanelHeight(animated: Bool) {
        let previous = measuredPanelHeight
        measuredPanelHeight = measurePermissionHeight()
        guard measuredPanelHeight != previous else { return }
        guard state == .panel else { return }  // the next `applyEffects` will use it
        resizeToContent(animated: animated)
    }

    /// The height the panel's current content lays out to, at panel width.
    private func measurePermissionHeight() -> CGFloat? {
        // The buddy's seat is reserved by the shared header, so its height is part of
        // what gets measured.
        let buddyBox = geometry.map {
            PillLayout.resolve(geometry: $0, buddy: buddy, sessionCount: sessionCount)
                .buddyBox
        } ?? .zero
        let header = PanelHeader(
            buddy: buddy, expression: expression, buddyBox: buddyBox,
            sessions: sessions, budget: budget, l10n: l10n,
            onSettings: {}, onQuit: {})

        let content: AnyView
        if let consent = permissions.consent {
            content = AnyView(PermissionConsentView(
                rule: consent.rule, diff: consent.diff,
                backupDirectory: consent.backupDirectory, l10n: l10n,
                onCancel: {}, onConfirm: {}))
        } else if let permission = permissions.permission {
            content = AnyView(PermissionPanelView(
                model: permission, waiting: permissions.waiting, measuring: true,
                l10n: l10n, onDeny: {}, onAllow: {}, onAlwaysAllow: {}, onAnswer: { _ in }))
        } else {
            // The sessions view is laid out against the full box; it does not ask for a
            // size, it is given one.
            return nil
        }

        // The same wrapper the screen draws, header and padding included — measuring
        // the body alone and adding a guessed header height is how the number drifts
        // from what is on screen.
        let width = Self.panelMaxSize.width
        let host = NSHostingView(
            rootView: DeployedPanel(header: header) { content }.frame(width: width))
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        return height > 0 ? height : nil
    }

    /// Animates the window to the height the content asked for, without disturbing
    /// anything else about the state.
    private func resizeToContent(animated: Bool) {
        guard let target = targetFrame(for: .panel) else { return }
        let generation = machine.nextGeneration()
        hover.pillRect = hoverRect(for: .panel)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion else {
            setFrameImmediately(target)
            finishStateChange(generation: generation)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = PanelTiming.collapse
            ctx.timingFunction = Self.expandCurve
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishStateChange(generation: generation) }
        }
    }

    private func answerPermission(_ decision: HookDecision?) {
        permissions.answer(decision)
    }

    /// Draws the consent screen when the router says there is one to show.
    private func alwaysAllowPermission() {
        guard permissions.alwaysAllow() else { return }
        rebuildContent()
        refreshPanelHeight(animated: true)
    }

    private func cancelConsent() {
        permissions.cancelConsent()
        rebuildContent()
        refreshPanelHeight(animated: true)
    }

    /// No visual effect of its own: the write and the answer both happen in the router,
    /// and the queue comes back through `setPermission` with whatever is next.
    private func confirmConsent() {
        permissions.confirmConsent()
    }

    /// Identifier of the buddy currently loaded.
    var currentBuddyID: String { buddy?.id ?? "—" }

    func setBuddy(_ manifest: BuddyManifest) {
        buddy = manifest
        machine.apply(animated: false)
    }

    func setLanguage(_ strings: Strings, locale: Locale) {
        self.l10n = strings
        self.locale = locale
        machine.apply(animated: false)
    }

    func setLayoutPrefs(groupByDirectory: Bool, jumpOnClick: Bool, showUsage: Bool) {
        guard groupByDirectory != self.groupByDirectory
            || jumpOnClick != self.jumpOnClick
            || showUsage != self.showUsage
        else { return }
        self.groupByDirectory = groupByDirectory
        self.jumpOnClick = jumpOnClick
        self.showUsage = showUsage
        if state == .panel { rebuildContent() }
    }

    func setJumpNote(_ note: String?) {
        guard note != jumpNote else { return }
        jumpNote = note
        if state == .panel { rebuildContent() }
    }

    func setUsage(_ status: UsageState.Status) {
        guard status != usage else { return }
        usage = status
        if state == .panel { rebuildContent() }
    }

    func setSessions(_ list: [AgentSession]) {
        guard list != sessions else { return }
        sessions = list
        // A chosen session that has since ended stops speaking for the face.
        if let chosen, !list.contains(where: { $0.id == chosen }) { self.chosen = nil }
        applyExpression()
        if state == .panel { rebuildContent() }
    }

    /// The session the user clicked, if any.
    private var chosen: String?

    private func select(_ id: String) {
        chosen = (chosen == id) ? nil : id
        applyExpression()
        rebuildContent()
    }

    /// Clears the choice.
    private func clearSelection() {
        guard chosen != nil else { return }
        chosen = nil
        applyExpression()
    }

    /// The face: the chosen session if there is one, the aggregate otherwise.
    private func applyExpression() {
        guard let chosen, let session = sessions.first(where: { $0.id == chosen }) else {
            if aggregateExpression != expression { setExpression(aggregateExpression) }
            return
        }
        let state = SessionDisplayState.of(session)
        setExpression(BuddyExpression.from(
            activity: state.activity, hasLiveSession: session.isLive, isVisible: true))
    }

    /// What the face would show with nobody chosen.
    private var aggregateExpression: BuddyExpression = .sleeping

    func setSessionCount(_ count: Int) {
        guard count != sessionCount else { return }
        sessionCount = count
        // The counter feeds the pill width: `×9` and `×10` differ.
        machine.apply(animated: false)
    }

    /// Called by the coordinator with the aggregate.
    func setAggregateExpression(_ next: BuddyExpression) {
        aggregateExpression = next
        guard chosen == nil else { return }
        setExpression(next)
    }

    /// Frames the face needs right now.
    ///
    /// A chase is the one thing a resting face does that has to be drawn properly: the
    /// eyes track the pointer and the colour runs to pink, and at the ambient 8 fps of a
    /// sleeping buddy that reads as a stutter rather than as a chase. So the tier
    /// follows the mood as well as the expression.
    private func refreshAnimationBudget() {
        // Three reasons to draw at full rate, and one place that knows all three. The
        // state and the expression each had their own call before, so whichever ran
        // last decided — an open panel dropped to ambient the moment the face went idle.
        let working = expression != .sleeping && expression != .idle
        budget.update(
            isVisible: state.isVisible,
            isBusy: state == .panel || working || gaze.isAnimating())
    }

    /// Drops the frame rate back once the pointer has been still long enough for the
    /// chase to have faded. Re-armed by every sample, so a chase that is still being led
    /// never lowers it.
    private func scheduleChaseWindDown() {
        chaseWindDown?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refreshAnimationBudget() }
        }
        chaseWindDown = work
        // The rest delay plus the fade: the exact moment `mood` stops returning
        // `.chasing`, so the frames stop being needed and not a moment before.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PointerGazeState.restDelay + PointerGazeState.chaseFade,
            execute: work)
    }

    func setExpression(_ wanted: BuddyExpression) {
        // A panel that is waiting on a person shows an available face. Whatever the
        // sessions are doing behind it, the thing on screen is a question addressed to
        // the user: a face that keeps working, or one that shows the red of a failure
        // that has nothing to do with what is being asked, reads as the app being busy
        // with something else.
        let next = isHoldingAnAsk ? .idle : wanted
        guard next != expression else { return }
        expression = next
        refreshAnimationBudget()
        updateGaze()
        rebuildContent()
    }

    /// Who reacts to the pointer, and how.
    private func updateGaze() {
        let follows = expression == .idle || expression == .finished
        let wanted = state.isVisible
        gaze.isEnabled = wanted
        gaze.followsPointer = follows
        gaze.anchor = wanted ? buddyScreenRect : .zero
        // The bands are read off the display the face is on, so a second monitor of
        // another size divides in the same places.
        gaze.screen = wanted ? (screen ?? NSScreen.main)?.frame ?? .zero : .zero
        pointer.setActive(wanted)
    }

    /// A shake reaches every face, `sleeping` included, so the frames have to follow it
    /// there too.
    private func pointerDidSample() {
        guard gaze.isAnimating() else { return }
        refreshAnimationBudget()
        scheduleChaseWindDown()
    }

    /// Where the face itself is on screen — the ear, not the whole pill, and the
    /// header's seat once the panel is open.
    private var buddyScreenRect: CGRect {
        let shell = pillScreenRect
        guard let geometry, let buddy else { return shell }
        let layout = PillLayout.resolve(
            geometry: geometry, buddy: buddy, sessionCount: sessionCount)
        let box = layout.buddyBox
        guard box.width > 0 else { return shell }

        let origin: CGPoint = state == .panel
            ? CGPoint(x: shell.minX + PanelMetrics.contentInset.width,
                      y: shell.maxY - PanelMetrics.contentInset.height - box.height)
            : CGPoint(x: shell.minX + (layout.leftWidth - box.width) / 2,
                      y: shell.maxY - (shell.height + box.height) / 2)
        return CGRect(origin: origin, size: box)
    }

    /// What counts as clicking on the buddy. Grown a little: the face is 62×30, and
    /// asking for a hit inside exactly that is asking for a miss.
    private var buddyClickRect: CGRect { buddyScreenRect.insetBy(dx: -8, dy: -8) }

    /// Show an alert in the pill for a few seconds.
    func present(_ alert: SessionAlert, for duration: TimeInterval = 4) {
        guard state == .pill || state == .speech else { return }
        alertDismissal?.cancel()
        currentAlert = alert
        setState(.speech)
        rebuildContent()

        let dismissal = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state == .speech else { return }
                self.currentAlert = nil
                self.setState(.pill)
            }
        }
        alertDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissal)
    }

    /// Re-resolve after a display is plugged, unplugged or rearranged.
    func refreshGeometry() {
        let resolved = NotchGeometry.resolve(preferredScreenID: geometry?.screenID)
        guard resolved != geometry else { return }
        geometry = resolved
        if state != .hidden { machine.apply() }
    }

    override func mouseDown(with event: NSEvent) {
        // `host` fills the window, so its coordinates are the window's.
        dragArmed = host.absorbingRect.contains(event.locationInWindow)
        guard dragArmed else { return }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = frame.origin
        dragTravel = 0
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragArmed, let geometry else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        dragTravel = max(dragTravel, hypot(dx, dy))
        guard dragTravel >= Self.dragThreshold else { return }
        isDragging = true

        let originX = dragStartOrigin.x + dx
        anchorFraction = NotchFrameSolver.fraction(
            forOriginX: originX, size: frame.size, geometry: geometry
        )
        setFrame(
            NotchFrameSolver.frame(size: frame.size, geometry: geometry, fraction: anchorFraction),
            display: true, animate: false
        )
        snapPreview.show(fraction: anchorFraction, size: frame.size, geometry: geometry)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragArmed = false }
        snapPreview.hide()
        // A click that went nowhere is a poke, and a poke on the face is funny.
        if !isDragging, buddyClickRect.contains(NSEvent.mouseLocation) {
            gaze.amuse()
        }
        guard isDragging, let geometry else { return }
        isDragging = false
        anchorFraction = NotchFrameSolver.snap(
            fraction: anchorFraction, size: frame.size, geometry: geometry
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().setFrame(
                NotchFrameSolver.frame(size: frame.size, geometry: geometry, fraction: anchorFraction),
                display: true
            )
        }
        hover.pillRect = pillScreenRect
    }
}
