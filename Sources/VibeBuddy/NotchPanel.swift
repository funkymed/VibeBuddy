import AppKit
import SwiftUI
import VibeBuddyKit
import VibeHookProtocol

/// The window. Geometry arithmetic lives in `NotchFrameSolver`, where it is
/// testable without a display. One state, exactly one frame per transition.
@MainActor
final class NotchPanel: NSPanel {

    /// The largest the panel gets: the sessions view is written to this, and a
    /// permission never grows past it — the text was already cut at parse time,
    /// but a diff of forty lines would still ask for a window taller than the
    /// screen.
    static let panelMaxSize = CGSize(width: 560, height: 460)
    /// The smallest. Below this the header, one line of summary and the
    /// decision bar start crowding each other, and a panel that changes height
    /// by twenty points between two requests reads as jitter rather than as
    /// fit.
    static let panelMinHeight: CGFloat = 200
    /// Kept at panel width even in pill state, so the transition never jumps
    /// horizontally. `ClickThroughHostView` keeps the margins click-through.
    static let carrierWidth: CGFloat = 560

    /// What the panel is actually sized to right now.
    ///
    /// Width never varies. Height follows what a permission needs and falls
    /// back to the full box for the sessions view, which is laid out against
    /// it. Clamped both ways: `panelMinHeight` keeps a one-line request from
    /// looking like a mistake, `panelMaxSize.height` keeps a long diff on the
    /// screen.
    var panelSize: CGSize {
        guard let measured = measuredPanelHeight else { return Self.panelMaxSize }
        return CGSize(
            width: Self.panelMaxSize.width,
            height: min(max(measured, Self.panelMinHeight), Self.panelMaxSize.height))
    }

    /// The height the permission panel asked for, or nil when the panel is not
    /// showing one. Recomputed when what it shows changes, never per frame.
    private var measuredPanelHeight: CGFloat?

    private typealias Host = ClickThroughHostView<NotchShellView>

    private let wake: WakeCoordinator
    private let budget: AnimationBudget
    private let hover: HoverProbe
    /// Do not erase to `AnyView`: it boxes on every rebuild and destroys the
    /// structural comparison SwiftUI uses to skip untouched subtrees.
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
    /// Clicking a live session row. The pid is the agent's, not the terminal's.
    var onJump: (pid_t) -> Void = { _ in }
    private var jumpNote: String?
    /// The permission on screen, and what answering it does. Held as plain
    /// values like the rest of the panel's inputs: observing the queue would
    /// re-evaluate this view on every change to it.
    private var permission: PermissionRequestModel?
    private var permissionWaiting = 0
    var onPermissionDecision: ((String, HookDecision?) -> Void)?
    /// Asked to build the consent for a request, and to write it once confirmed.
    /// Held as closures so the panel never learns the shape of the settings file.
    var onPermissionAlwaysAllowAsked: ((PermissionRequestModel) -> PermissionConsent?)?
    var onConsentConfirmed: ((PermissionConsent) -> Void)?
    private var consent: PermissionConsent?
    /// Panel-facing preferences (RFC-010), held as plain values: observing the
    /// models would re-evaluate the view on every preference write.
    private var groupByDirectory = true
    private var jumpOnClick = true
    private var showUsage = true

    /// Suppresses hover while another surface of ours owns the screen.
    ///
    /// Do not pin the panel open over the settings window: `.floating` (3) is
    /// below `.statusBar` (25), so the panel covers what it just opened.
    /// See RFC-002, « Notes d'implémentation ».
    /// True from the moment the panel starts growing until it has finished.
    ///
    /// Both hover sources lag during the growth — the tracking area is built
    /// against `bounds`, which follows the resize, and the probe against a rect
    /// that is only correct once it settles. Neither is allowed to close a
    /// panel that has not finished opening; the probe is a poll, so if the
    /// pointer really has left it says so again on its next tick.
    private var opening = false

    /// Whether the settings window is on screen.
    ///
    /// It used to be `suppressesHover`, and it collapsed the panel: the
    /// settings were pinned one level above `.statusBar`, so a deployed panel
    /// could only hide them. With the window back at `.normal`, there is
    /// nothing to protect — and being unable to open the notch while its own
    /// settings are on screen is exactly the moment you want to look at it.
    ///
    /// What it still does is keep the panel from taking the key status away
    /// from the window the user is typing in. See `scheduleKeyIfDeployed`.
    var settingsAreOpen = false
    private var usage: UsageState.Status = .unknown
    private var l10n: Strings = .french
    private var locale: Locale = .current
    private var alertDismissal: DispatchWorkItem?

    private(set) var geometry: NotchGeometry?
    private var anchorFraction: CGFloat = 0.5

    private(set) var state: PanelState = .hidden {
        didSet { if state != oldValue { applyState() } }
    }

    private static let expandCurve = CAMediaTimingFunction(name: .easeOut)

    private static let dragThreshold: CGFloat = 5
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var dragTravel: CGFloat = 0
    private var isDragging = false
    /// Do not drop this guard: `hitTest` returning nil still delivers the event
    /// to the *window*, so a menu-bar click through a margin also drags the pill.
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

        // **Dark, whatever the system is set to.**
        //
        // The panel is drawn on the black of the notch, but AppKit dresses its
        // own controls from the window's appearance — and in light mode a
        // scroller is dark grey on a light track, which on this background is
        // black on black. The indicator was there and invisible; `.visible`
        // scroll indicators were being asked for and rendered into nothing.
        //
        // Forcing `darkAqua` is the whole fix, and it is the honest one: this
        // window *is* a dark surface, permanently, in every system theme.
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

        // The poll below is the safety net: a pointer warped by a hotkey emits
        // no enter event at all.
        host.onHoverChange = { [weak self] hovering in
            guard let self else { return }
            self.logHover(source: "zone", hovering: hovering)
            if hovering, state == .pill { state = .panel }
            else if !hovering, state == .panel, !self.opening, !self.isHoldingAnAsk {
                state = .pill
            }
        }

        hover.onChange = { [weak self] hovering in
            guard let self else { return }
            self.logHover(source: "sonde", hovering: hovering)
            if hovering, state == .pill { state = .panel }
            else if !hovering, state == .panel, !self.opening, !self.isHoldingAnAsk {
                state = .pill
            }
        }

        refreshGeometry()
        rebuildContent()
    }

    /// Whether the panel is holding something that waits on a **person**.
    ///
    /// A panel opened by hovering closes when the pointer leaves — that is what
    /// hovering means. A panel that opened by itself to ask a question did not
    /// come from the pointer, and it does not go with it: the user reads the
    /// question, looks away, goes back to their terminal to check something,
    /// and comes back. Closing under them mid-thought is the same mistake as
    /// the « terminal au premier plan » expiry of 2026-08-21 — an alert may be
    /// withdrawn, a question may not. It leaves when it is answered, and by no
    /// other route.
    ///
    /// The pointer can still open the panel; only the closing is held.
    private var isHoldingAnAsk: Bool { permission != nil || consent != nil }

    /// **Key while the panel is open, never while it is a pill.**
    ///
    /// It was flatly `false`, to keep the terminal's keyboard focus. The cost
    /// turned out to be the pointer: macOS lets only the frontmost application
    /// put a cursor on screen, so `NSCursor.set()` from here was executed and
    /// discarded — traced, with the zones resolving correctly and the hand
    /// requested on every move. No amount of ordering or re-asserting fixes
    /// that; the window has to be key.
    ///
    /// `.nonactivatingPanel` is what makes this affordable: such a panel becomes
    /// key **without activating the application**, so the terminal underneath
    /// keeps the keyboard. Restricted to the deployed state so the pill, which
    /// is on screen all day, never takes it.
    override var canBecomeKey: Bool { state == .panel }
    override var canBecomeMain: Bool { false }

    // MARK: - State

    func show() {
        guard state == .hidden else { return }
        state = .pill
    }

    func hide() {
        guard state != .hidden else { return }
        state = .hidden
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

    private var frameGeneration = 0

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

    /// Do not use `setFrame(_:display:animate:false)` here: an in-flight
    /// `animator()` keeps driving the window and it lands at the old target.
    private func setFrameImmediately(_ target: CGRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            animator().setFrame(target, display: true)
        }
    }

    /// Takes the key status on the next run-loop turn, if the panel still wants
    /// it by then. See the note in `applyState`.
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

    /// Guards against `applyState` being re-entered while it runs.
    ///
    /// It sets `host.hitRegion`, which rebuilds the tracking area, which can
    /// report hover, which changes `state`, whose `didSet` calls back in here.
    /// The inner call is deferred rather than run: the outer one has already
    /// computed a size and a target for the state it was leaving, and letting
    /// the two interleave is what left the panel stuck black. Once the outer
    /// call finishes, the deferred one runs against whatever the state is by
    /// then, so it converges.
    private var applying = false
    private var needsReapply = false
    private var reapplyDepth = 0

    private func applyState(animated: Bool = true) {
        if applying { needsReapply = true; return }
        applying = true
        defer {
            applying = false
            if needsReapply {
                needsReapply = false
                // **Bounded.** The deferred replay converges because the state
                // settles, but « converges » was an assumption, and an
                // assumption that is wrong here does not misdraw — it hangs the
                // main thread with a beachball, which is what happened. Ten is
                // far more than any real transition needs; reaching it means
                // something is oscillating, and stopping leaves the panel in a
                // state `finishStateChange` will correct.
                reapplyDepth += 1
                if reapplyDepth < 10 {
                    applyState(animated: animated)
                }
            }
            if !applying { reapplyDepth = 0 }
        }

        // Shadowed once so the whole body agrees with itself even if something
        // it calls changes the state underneath it.
        let state = self.state
        frameGeneration += 1
        let generation = frameGeneration
        let size = state == .panel ? panelSize : pillSize
        let carrier = CGSize(width: Self.carrierWidth, height: size.height)

        // Destination region up front: interpolating it drops the pointer out
        // of the growing panel and collapses it mid-open.
        host.hitRegion = hitRegion(for: state)
        // The probe needs the same treatment, and did not have it: its rect was
        // only reassigned once the animation had finished, so for the whole
        // growth it compared the pointer against the 38 pt pill. Moving the
        // pointer *down into* the opening panel left that rect and collapsed it.
        hover.pillRect = hoverRect(for: state)
        opening = state == .panel

        // **Unfused mouse movement while the panel is open.**
        //
        // AppKit merges mouse-moved events by default: swept quickly, a whole
        // run of positions arrives as a single event carrying the last one, and
        // every control the pointer crossed on the way is never told. That is
        // the « je glisse d'un bouton à l'autre sans m'arrêter et ça ne passe
        // pas en hover » — the events for the buttons in between did not exist.
        //
        // Turned off only while the panel is deployed, which is the only state
        // with anything to hover, and the only one where the extra events are
        // worth their cost. Restored on the way back to the pill so the resting
        // budget is untouched.
        NSEvent.isMouseCoalescingEnabled = (state != .panel)

        if state.isVisible { orderFrontRegardless() }
        // Key only while deployed, and only so the cursor can be ours. See
        // `canBecomeKey`. The pill never asks.
        //
        // **Never `resignKey()`.** It is a notification AppKit sends, not a
        // command it takes: « you should never invoke this method directly ».
        // Calling it here crashed the app every time the settings window
        // opened, and for a reason worth remembering — `settings.show()` makes
        // that window key, which sets `suppressesHover`, which collapses this
        // panel, which ran `resignKey()` **in the middle of AppKit's own key
        // transition**. Two parties resigning the same window at once.
        //
        // Nothing is needed in its place: `canBecomeKey` is already false once
        // the panel is not deployed, and the window that asked for the focus
        // takes it. Measured before all this: the frontmost application stays
        // the terminal throughout.
        //
        // Not while the settings own the screen either, or this panel would
        // pull the focus back from the window the user just opened.
        //
        // **Deferred, and never from inside `applyState`.** Taking the key
        // status makes AppKit send notifications, which reach the hover path,
        // which changes `state`, whose `didSet` re-enters here — and the
        // re-entry guard below faithfully replays the call, which takes the key
        // again. That loop is what froze the app on the beachball when the
        // settings window opened. Asking for it on the next turn of the run
        // loop, against whatever the state is by then, cannot recurse.
        scheduleKeyIfDeployed()

        // Closing the panel ends the question, so the face goes back to
        // speaking for everything rather than for one session.
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
        // Never skip the frame change on `frame.size == carrier`: mid-animation
        // the window passes through the target size, and a collapse taking that
        // shortcut left it at 460 pt while the state said pill — a 38 pt hover
        // strip became a 460 pt column.
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

    /// Width animates in SwiftUI, height on the `NSWindow`: same duration, same
    /// curve, same run-loop turn, or the shape stretches before it settles.
    private func growTogether(
        to target: CGRect?, drawnWidth: CGFloat, growing: Bool, generation: Int
    ) {
        let duration = growing ? PanelTiming.expand : PanelTiming.collapse

        // Nothing to grow from on the very first appearance. `drawnWidth`
        // starts at zero, and `NotchShellView` wraps the three fixed slots —
        // ear, cutout, ear — in a frame of that width. A frame narrower than
        // its content centres it, so animating 0 → 404 slides both ears in
        // from the middle and the buddy spends a quarter of a second cut in
        // half: at launch you saw one eye instead of two.
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
        if let generation, generation != frameGeneration { return }

        // Last line of defence: both hover regions are read from the frame.
        if state != .hidden, let target = targetFrame(for: state), frame != target {
            setFrameImmediately(target)
        }

        // Re-assert on the settled frame: `applyState` set it before the resize.
        host.hitRegion = hitRegion(for: state)
        host.refreshTrackingNow()

        opening = false

        // The panel is open and the animation is over, so whatever became of
        // the reveal work item, the content belongs on screen now. Without
        // this the shape is drawn — it always is — while both contents are
        // skipped, and an open panel with nothing in it is a black rectangle.
        // Never show a shape with no content in it.
        if state == .panel, !contentRevealed {
            revealWork?.cancel()
            contentRevealed = true
            rebuildContent()
        }

        onPanelVisibilityChange?(state == .panel)
        updateGaze()
        hover.pillRect = pillScreenRect
        hover.setActive(state.isVisible)
        budget.update(isVisible: state.isVisible, isBusy: state == .panel)
    }
    /// Hover opens the panel from `.pill` **and from `.speech`**.
    ///



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

    // MARK: - Diagnostics

    /// The three rects that decide when the panel opens, for `--hover`.
    var debugTrackingRect: CGRect { host.absorbingRect }
    /// What the view really paints, scanned from its own bitmap.
    var debugPaintedRect: CGRect { HoverDiagnostics.paintedRect(of: host) }
    var debugPolledRect: CGRect { hover.pillRect }
    func debugSetState(_ next: PanelState) { state = next }
    var debugState: String { String(describing: state) }

    /// Screen-space rect of the visible pill, which is narrower than the window.
    /// The rect the probe tests against, taken from where the window is
    /// **going** rather than where it currently is.
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
                       jumpNote: jumpNote,
                       gaze: gaze,
                       permission: permission, permissionWaiting: permissionWaiting,
                       onPermissionDeny: { [weak self] in self?.answerPermission(.deny(message: self?.l10n.permissionDenied ?? "")) },
                       onPermissionAllow: { [weak self] in self?.answerPermission(.allow) },
                       onPermissionAlwaysAllow: { [weak self] in self?.alwaysAllowPermission() },
                       onPermissionAnswer: { [weak self] in self?.answerPermission(QuestionAnswer.decision(for: $0)) },
                       consent: consent,
                       onConsentCancel: { [weak self] in self?.cancelConsent() },
                       onConsentConfirm: { [weak self] in self?.confirmConsent() },
                       groupByDirectory: groupByDirectory,
                       jumpOnClick: jumpOnClick, showUsage: showUsage,
                       panelHeight: state == .panel ? panelSize.height : 0)
    }

    private func rebuildContent() {
        host.hosting.rootView = shellView
    }

    // MARK: - Permissions

    /// Shows a request, or takes the last one away.
    ///
    /// A request **forces the panel open** and holds it there: it is the one
    /// thing more urgent than whatever the user was doing with the notch. When
    /// the last one goes, the panel returns to the pill rather than falling
    /// back to the session list — the user did not ask for that list, a
    /// permission put the panel on screen.
    func setPermission(_ model: PermissionRequestModel?, waiting: Int) {
        let had = permission != nil
        guard model?.id != permission?.id || waiting != permissionWaiting else { return }
        permission = model
        permissionWaiting = waiting

        // The request went away under the consent screen — expired, or
        // answered in the terminal. There is nothing left to grant.
        let hadConsent = consent != nil
        if model == nil, hadConsent { consent = nil }

        // Measured once everything the panel shows has settled, and
        // **unconditionally**. Left over from a request that is gone, it would
        // size the sessions view to a permission nobody is looking at any more:
        // answer a question, hover the notch again, and the panel opens at the
        // height of the question instead of its own. `nil` is what puts the
        // full box back, and only measuring on the way in never produces it.
        //
        // Before the state moves, too: `applyState` reads `panelSize`, so the
        // panel opens at the right height rather than opening at the full box
        // and shrinking into place.
        measuredPanelHeight = measurePermissionHeight()

        if model != nil {
            if state != .panel {
                state = .panel
            } else {
                // Already open on another request. Swap the content, then move
                // the frame to what the new one needs.
                rebuildContent()
                resizeToContent(animated: true)
            }
        } else if hadConsent || had {
            state = .pill
        } else {
            rebuildContent()
        }

        // The face was pinned to `idle` while the ask was up; put back whatever
        // the sessions are actually doing now that it is gone.
        applyExpression()
    }

    // MARK: - Sizing to what is on screen

    /// Measures what the permission panel wants, and moves the window to it.
    ///
    /// Called when what the panel *shows* changes — a request arrives, another
    /// takes its place, the consent screen opens or closes — and never per
    /// frame.
    private func refreshPanelHeight(animated: Bool) {
        let previous = measuredPanelHeight
        measuredPanelHeight = measurePermissionHeight()
        guard measuredPanelHeight != previous else { return }
        guard state == .panel else { return }  // the next `applyState` will use it
        resizeToContent(animated: animated)
    }

    /// The height the panel's current content lays out to, at panel width.
    ///
    /// Measured off screen on a throwaway host rather than read back from the
    /// live one: the view being measured is not the view being shown, so its
    /// height is free, and nothing it reports can feed back into the frame it
    /// was measured at. Width is fixed and does not depend on height, so this
    /// settles in one pass.
    ///
    /// `AnyView` here is deliberate and does not contradict D2's ban on it:
    /// that ban is about the *displayed* host, where boxing destroys the
    /// structural comparison SwiftUI uses to skip untouched subtrees. This host
    /// is built once per request, asked its size, and dropped.
    private func measurePermissionHeight() -> CGFloat? {
        // The buddy's seat is reserved by the shared header, so its height is
        // part of what gets measured. `alertText` is left out: it widens the
        // ears, it does not change the seat.
        let buddyBox = geometry.map {
            PillLayout.resolve(geometry: $0, buddy: buddy, sessionCount: sessionCount)
                .buddyBox
        } ?? .zero
        let header = PanelHeader(
            buddy: buddy, expression: expression, buddyBox: buddyBox,
            sessions: sessions, budget: budget, l10n: l10n,
            onSettings: {}, onQuit: {})

        let content: AnyView
        if let consent {
            content = AnyView(PermissionConsentView(
                rule: consent.rule, diff: consent.diff,
                backupDirectory: consent.backupDirectory, l10n: l10n,
                onCancel: {}, onConfirm: {}))
        } else if let permission {
            content = AnyView(PermissionPanelView(
                model: permission, waiting: permissionWaiting, measuring: true,
                l10n: l10n, onDeny: {}, onAllow: {}, onAlwaysAllow: {}, onAnswer: { _ in }))
        } else {
            // The sessions view is laid out against the full box; it does not
            // ask for a size, it is given one.
            return nil
        }

        // The same wrapper the screen draws, header and padding included —
        // measuring the body alone and adding a guessed header height is how
        // the number drifts from what is on screen.
        let width = Self.panelMaxSize.width
        let host = NSHostingView(
            rootView: DeployedPanel(header: header) { content }.frame(width: width))
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        return height > 0 ? height : nil
    }

    /// Animates the window to the height the content asked for, without
    /// disturbing anything else about the state.
    ///
    /// Deliberately **not** a call to `applyState`: that one hides the content
    /// and schedules it back in, which is right when the panel opens and wrong
    /// here — a second request arriving while the first is on screen would make
    /// the whole panel blink. What it does borrow is the two things that must
    /// never lag behind the frame: the hover rect is set to the *destination*
    /// (a probe still holding the old rect closes a panel the pointer is inside
    /// of), and `finishStateChange` re-asserts the tracking area on the settled
    /// frame.
    private func resizeToContent(animated: Bool) {
        guard let target = targetFrame(for: .panel) else { return }
        frameGeneration += 1
        let generation = frameGeneration
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
        guard let id = permission?.id else { return }
        onPermissionDecision?(id, decision)
    }

    /// « Toujours autoriser » is a decision **and** a write to the user's own
    /// settings. The two are separated on purpose: this shows the exact diff
    /// and waits (T8). Nothing is written until it comes back confirmed.
    ///
    /// When there is nothing to write — the rule is already granted — it is
    /// simply an allow, with no screen in the way.
    private func alwaysAllowPermission() {
        guard let model = permission,
              let pending = onPermissionAlwaysAllowAsked?(model)
        else { answerPermission(.allow); return }
        consent = pending
        rebuildContent()
        refreshPanelHeight(animated: true)
    }

    private func cancelConsent() {
        consent = nil
        rebuildContent()
        refreshPanelHeight(animated: true)
    }

    /// Writes, then answers. In that order: an allow that reached Claude Code
    /// before the rule was on disk would be granted once and asked again next
    /// time, which reads as the button not working.
    private func confirmConsent() {
        guard let pending = consent else { return }
        consent = nil
        onConsentConfirmed?(pending)
        answerPermission(.allow)
    }

    /// Identifier of the buddy currently loaded.
    var currentBuddyID: String { buddy?.id ?? "—" }

    func setBuddy(_ manifest: BuddyManifest) {
        buddy = manifest
        applyState(animated: false)
    }

    func setLanguage(_ strings: Strings, locale: Locale) {
        self.l10n = strings
        self.locale = locale
        applyState(animated: false)
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

    /// The session the user clicked, if any. While one is chosen the face shows
    /// *that* session rather than the aggregate: you asked about this one, so
    /// the buddy answers about this one.
    private var chosen: String?

    private func select(_ id: String) {
        chosen = (chosen == id) ? nil : id
        applyExpression()
        rebuildContent()
    }

    /// Clears the choice. The panel closing means the question is over.
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

    /// What the face would show with nobody chosen. Kept so the choice can be
    /// undone without waiting for the next refresh.
    private var aggregateExpression: BuddyExpression = .sleeping

    func setSessionCount(_ count: Int) {
        guard count != sessionCount else { return }
        sessionCount = count
        // The counter feeds the pill width: `×9` and `×10` differ.
        applyState(animated: false)
    }

    /// Called by the coordinator with the aggregate. Remembered, then applied
    /// only if the user has not chosen a session to follow instead.
    func setAggregateExpression(_ next: BuddyExpression) {
        aggregateExpression = next
        guard chosen == nil else { return }
        setExpression(next)
    }

    func setExpression(_ wanted: BuddyExpression) {
        // **A panel that is waiting on a person shows an available face.**
        // Whatever the sessions are doing behind it, the thing on screen is a
        // question addressed to the user: a face that keeps working, or one
        // that shows the red of a failure that has nothing to do with what is
        // being asked, reads as the app being busy with something else. `idle`
        // also follows the pointer (see `updateGaze`), which is the right
        // answer to « this is for you ».
        //
        // The aggregate is still remembered in `aggregateExpression`, so
        // `applyExpression` puts the real face back the moment the ask leaves.
        let next = isHoldingAnAsk ? .idle : wanted
        guard next != expression else { return }
        expression = next
        budget.update(isVisible: state.isVisible, isBusy: next != .sleeping && next != .idle)
        updateGaze()
        rebuildContent()
    }

    /// Who reacts to the pointer, and how.
    ///
    /// `idle` and `finished` follow it: they have nothing better to do. Working
    /// does **not** — a face that is working should look busy, not
    /// distractible.
    ///
    /// A **shake** gets through to all of them and starts a chase, working or
    /// not: one gesture, one meaning. **`sleeping` included**, since
    /// 2026-08-22: it used to be excluded on the grounds that it carries no
    /// clock, but the clock is `AnimationBudget`'s and it is already `.ambient`
    /// whenever the pill is on screen — the sleeping *face* draws no motion of
    /// its own, which is not the same thing. A buddy you cannot wake by
    /// shaking at it is a toy that is broken, and waking it is the one gesture
    /// anybody tries first.
    ///
    /// It still does not **follow** the pointer while asleep: an ordinary
    /// movement leaves it alone, exactly as `working` is left alone. Only the
    /// shake gets through.
    ///
    /// **Cost:** `PointerMonitor` is now armed whenever the pill is visible,
    /// including with no session at all. It is silent while the pointer is
    /// still — that is why it is a monitor and not a poll — so the resting
    /// budget should not move. Should, not does: `make perf` scenario A has not
    /// been run since.
    private func updateGaze() {
        let follows = expression == .idle || expression == .finished
        let wanted = state.isVisible
        gaze.isEnabled = wanted
        gaze.followsPointer = follows
        gaze.anchor = wanted ? buddyScreenRect : .zero
        // The bands are read off the display the face is on, so a second
        // monitor of another size divides in the same places.
        gaze.screen = wanted ? (screen ?? NSScreen.main)?.frame ?? .zero : .zero
        pointer.setActive(wanted)
    }

    /// Where the face itself is on screen — the ear, not the whole pill, and
    /// the header's seat once the panel is open.
    ///
    /// Both seats, because the buddy travels between them and this rect is what
    /// decides whether a click landed on it. It only knew the collapsed one,
    /// which is the one the pointer is never over: hovering opens the panel, so
    /// by the time anybody clicks, the face has already moved.
    ///
    /// The same two positions `NotchShellView.buddyOrigin` interpolates
    /// between, read from the same constants.
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

    /// What counts as clicking on the buddy. Grown a little: the face is 62×30,
    /// and asking for a hit inside exactly that is asking for a miss.
    private var buddyClickRect: CGRect { buddyScreenRect.insetBy(dx: -8, dy: -8) }

    /// Show an alert in the pill for a few seconds. Never interrupts an open panel.
    func present(_ alert: SessionAlert, for duration: TimeInterval = 4) {
        guard state == .pill || state == .speech else { return }
        alertDismissal?.cancel()
        currentAlert = alert
        state = .speech
        rebuildContent()

        let dismissal = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state == .speech else { return }
                self.currentAlert = nil
                self.state = .pill
            }
        }
        alertDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissal)
    }

    // MARK: - Screens

    /// Re-resolve after a display is plugged, unplugged or rearranged.
    func refreshGeometry() {
        let resolved = NotchGeometry.resolve(preferredScreenID: geometry?.screenID)
        guard resolved != geometry else { return }
        geometry = resolved
        if state != .hidden { applyState() }
    }

    // MARK: - Drag

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
        // A click that went nowhere is a poke, and a poke on the face is
        // funny. Checked before the drag bail-out below, which returns early
        // precisely when nothing was dragged.
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
