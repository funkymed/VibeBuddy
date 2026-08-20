import AppKit
import SwiftUI
import NotchBuddyKit

/// The window. Holds no geometry arithmetic — that lives in `NotchFrameSolver`,
/// where it can be tested without a display.
///
/// Everything the reference implementation patched with flags is handled here by
/// having a single state and applying exactly one frame per transition. There is
/// no `suppressPrefsReposition`, and no `updateCollapsed` that quietly does
/// nothing while expanded, because there is no race left for them to paper over.
@MainActor
final class NotchPanel: NSPanel {

    static let panelSize = CGSize(width: 560, height: 460)
    /// The window is kept at panel width even while showing the pill, so the
    /// transition never jumps horizontally. `ClickThroughHostView` is what stops
    /// the invisible margins from eating menu-bar clicks.
    static let carrierWidth: CGFloat = 560

    private let wake: WakeCoordinator
    private let budget: AnimationBudget
    private let hover: HoverProbe
    private var host: ClickThroughHostView<AnyView>!
    private let snapPreview = SnapPreviewPanel()
    private let metrics = PanelMetrics()
    private var currentAlert: SessionAlert?
    private var buddy: BuddyManifest?
    private var expression: BuddyExpression = .sleeping
    private var sessionCount = 0
    private var sessions: [AgentSession] = []
    /// Whether the expanded contents are on screen. Lags the state deliberately.
    private var contentRevealed = false
    private var revealWork: DispatchWorkItem?
    /// What the panel's power button does. Set by the coordinator.
    var onQuit: () -> Void = { NSApp.terminate(nil) }
    var onSettings: () -> Void = {}
    /// Clicking a live session row. The pid is the agent's, not the terminal's.
    var onJump: (pid_t) -> Void = { _ in }
    private var jumpNote: String?
    /// Panel-facing preferences (RFC-010). Held as plain values rather than by
    /// observing the models: the panel redraws on its own schedule, and a view
    /// that re-evaluated on every preference write would be the invalidation
    /// problem this split exists to avoid.
    private var pixelSize: Double = Double(BuddyView.defaultPixelSize)
    private var groupByDirectory = true
    private var jumpOnClick = true
    private var showUsage = true

    /// Suppresses hover while another surface of ours owns the screen.
    ///
    /// The first attempt at this held the panel *open* while the settings window
    /// was up, so the user would not lose context. That was wrong twice over:
    /// the panel sits at `.statusBar` (25) and a floating window at 3, so the
    /// pinned panel simply covered the settings it had just opened — and two
    /// surfaces competing for the same screen is worse than one.
    ///
    /// It now collapses instead. One surface at a time, and hover stays inert so
    /// the pill does not re-expand under the settings window.
    var suppressesHover = false {
        didSet {
            guard suppressesHover != oldValue else { return }
            if suppressesHover, state == .panel { state = .pill }
        }
    }
    private var usage: UsageState.Status = .unknown
    private var l10n: Strings = .french
    private var locale: Locale = .current
    private var alertDismissal: DispatchWorkItem?

    private(set) var geometry: NotchGeometry?
    private var anchorFraction: CGFloat = 0.5

    private(set) var state: PanelState = .hidden {
        didSet { if state != oldValue { applyState() } }
    }

    // Drag bookkeeping. A press only becomes a drag past the threshold, so a
    // click never nudges the pill.
    /// `easeOut` rather than `easeInOut`: the panel should leave immediately and
    /// settle gently. An ease-*in* start reads as lag, because the gesture that
    /// triggered it already happened.
    private static let expandCurve = CAMediaTimingFunction(name: .easeOut)

    private static let dragThreshold: CGFloat = 5
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var dragTravel: CGFloat = 0
    private var isDragging = false
    /// Whether the press that started this gesture landed on the pill.
    ///
    /// `ClickThroughHostView.hitTest` returning nil means no *view* takes the
    /// event — but AppKit then delivers it to the *window*, which is this drag
    /// handler. Without this guard, clicking a menu-bar item through a
    /// transparent margin both opens the menu and drags the pill.
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

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isMovable = false
        acceptsMouseMovedEvents = true
        // Present on every Space, never dragged between them by Mission Control,
        // and visible over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        alphaValue = 0

        host = ClickThroughHostView(rootView: AnyView(EmptyView()))
        contentView = host

        // Event-driven hover. The poll below stays as a safety net for the case
        // a tracking area misses — a pointer teleported by a hotkey or a warp
        // generates no enter event.
        host.onHoverChange = { [weak self] hovering in
            guard let self, !self.suppressesHover else { return }
            self.logHover(source: "zone", hovering: hovering)
            if hovering, state == .pill { state = .panel }
            else if !hovering, state == .panel { state = .pill }
        }

        hover.onChange = { [weak self] hovering in
            guard let self, !self.suppressesHover else { return }
            self.logHover(source: "sonde", hovering: hovering)
            if hovering, state == .pill { state = .panel }
            else if !hovering, state == .panel { state = .pill }
        }

        refreshGeometry()
        rebuildContent()
    }

    /// Never key, never main.
    ///
    /// `.nonactivatingPanel` alone stops the app from activating on click, but
    /// the panel would still steal *key* status from the editor or terminal
    /// underneath — which is precisely what the user is looking at. The cost is
    /// that keyboard shortcuts inside the panel cannot work; buttons still do,
    /// because they fire on mouse events regardless of key state.
    override var canBecomeKey: Bool { false }
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

    /// Derived from the notch every time — see `NotchFrameSolver.pillSize`.
    /// Size of the drawn pill.
    ///
    /// Comes from the same `PillLayout` the content uses, so the frame and what
    /// is inside it cannot disagree. Sizing them separately is how a slot ends
    /// up clipped by a pill that was measured for different content.
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

    /// Bumped on every state change, so a completion handler can tell whether
    /// it belongs to the frame change still on screen.
    private var frameGeneration = 0

    /// The region that absorbs clicks and arms the hover, per state.
    ///
    /// Recomputed from `pillSize` each time rather than remembered: the pill's
    /// width follows the buddy and the counter, so a region captured once goes
    /// stale the first time a session appears.
    private func hitRegion(for state: PanelState) -> ClickThroughHostView<AnyView>.HitRegion {
        switch state {
        case .hidden: return .none
        case .panel: return .full
        case .pill, .speech: return .strip(width: pillSize.width, offsetX: 0)
        }
    }

    /// Where the window should sit for a given state.
    private func targetFrame(for state: PanelState) -> CGRect? {
        let size = state == .panel ? Self.panelSize : pillSize
        let carrier = CGSize(width: Self.carrierWidth, height: size.height)
        return geometry.map {
            NotchFrameSolver.frame(size: carrier, geometry: $0, fraction: anchorFraction)
        }
    }

    /// Set the frame **now**, superseding whatever animation is running.
    ///
    /// A plain `setFrame(_:display:animate:false)` does not do that: it moves
    /// the window, and the in-flight `animator()` keeps driving it afterwards,
    /// so the window ends up wherever the *old* animation was going. A
    /// zero-duration animation replaces the running one instead.
    private func setFrameImmediately(_ target: CGRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            animator().setFrame(target, display: true)
        }
    }

    private func applyState(animated: Bool = true) {
        frameGeneration += 1
        let generation = frameGeneration
        let size = state == .panel ? Self.panelSize : pillSize
        let carrier = CGSize(width: Self.carrierWidth, height: size.height)

        // Set the hit region to the destination up front. Interpolating it would
        // make the pointer fall out of the panel mid-grow and immediately
        // trigger a collapse — the panel would flicker instead of opening.
        host.hitRegion = hitRegion(for: state)

        if state.isVisible { orderFrontRegardless() }

        // Contents follow the frame rather than leading it — see
        // `PanelTiming.contentRevealFraction`.
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
            // Removed before the frame shrinks, not after.
            contentRevealed = false
        }

        // Swap the content *before* the frame moves, so the shape morphs with
        // the window instead of snapping at the end of the animation.
        rebuildContent()

        let target = targetFrame(for: state)

        // Respect the system setting. Someone who asked for less motion did not
        // ask for it only in other people's apps.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // `frame.size == carrier` is **not** a reason to skip the frame change.
        //
        // Mid-animation the window is momentarily whatever size the running
        // animation has reached, and one of those sizes is the size we are
        // heading back to. Treating that as "already there" was the bug: a
        // collapse asked for while the expansion was still growing took the
        // shortcut, the expansion kept running underneath, and the window
        // finished at panel size while the state said pill. The hover regions
        // are read from the window, so a 38 pt strip became a 460 pt column —
        // which arms the panel long before the pointer reaches the black, and
        // only ever after it has been opened once.
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

    /// Both axes at once.
    ///
    /// The width lives in SwiftUI and the height on the `NSWindow`, so this is
    /// two animation engines that have to land together: same duration, same
    /// curve, started in the same turn of the run loop. Any drift between them
    /// shows up as the shape stretching before it settles.
    private func growTogether(
        to target: CGRect?, drawnWidth: CGFloat, growing: Bool, generation: Int
    ) {
        let duration = growing ? PanelTiming.expand : PanelTiming.collapse

        withAnimation(.easeOut(duration: duration)) {
            metrics.drawnWidth = drawnWidth
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

    /// Everything that can only be settled once the frame has stopped moving —
    /// the hover rect in particular, which is read from the live frame.
    /// Told when the panel opens, so usage can be polled more tightly while
    /// someone is actually reading it.
    var onPanelVisibilityChange: ((Bool) -> Void)?

    private func finishStateChange(generation: Int? = nil) {
        // A completion from a superseded animation must not publish anything:
        // it would describe a frame the window has already left.
        if let generation, generation != frameGeneration { return }

        // The window is where the state says, or it is corrected here. This is
        // the last line of defence for the mid-animation races: everything
        // downstream — both hover regions — is read from the frame.
        if state != .hidden, let target = targetFrame(for: state), frame != target {
            setFrameImmediately(target)
        }

        // Re-assert the region on the settled frame. `applyState` sets it to
        // the destination up front — deliberately, so the pointer does not fall
        // out of a growing panel — and "up front" is by definition before the
        // window has the size the region describes.
        host.hitRegion = hitRegion(for: state)
        host.refreshTrackingNow()

        onPanelVisibilityChange?(state == .panel)
        hover.pillRect = pillScreenRect
        hover.setActive(state.isVisible)
        budget.update(isVisible: state.isVisible, isBusy: state == .panel)
    }

    /// Who armed the hover, where the pointer was, and what the regions were.
    ///
    /// Logged rather than reasoned about: two readings of the source produced
    /// two plausible causes and one fix that fixed nothing. The pointer against
    /// both regions, at the instant one of them fires, is what settles it.
    ///
    /// `log stream --predicate 'subsystem == "com.notchbuddy"' --info`
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
    private var pillScreenRect: CGRect {
        let f = frame
        let w = state == .panel ? Self.panelSize.width : pillSize.width
        return CGRect(x: f.midX - w / 2, y: f.minY, width: w, height: f.height)
    }

    private func rebuildContent() {
        host.hosting.rootView = AnyView(
            NotchShellView(state: state, geometry: geometry, budget: budget, metrics: metrics,
                           alert: currentAlert, buddy: buddy, expression: expression,
                           sessionCount: sessionCount, sessions: sessions,
                           showPanelContent: contentRevealed, usage: usage,
                           l10n: l10n, locale: locale,
                           onSettings: onSettings, onQuit: onQuit,
                           onJump: onJump, jumpNote: jumpNote,
                           pixelSize: pixelSize, groupByDirectory: groupByDirectory,
                           jumpOnClick: jumpOnClick, showUsage: showUsage)
        )
    }

    /// Install a buddy manifest. Safe to call at any time — the renderer is
    /// stateless, so swapping is just a redraw.
    /// Identifier of the buddy currently loaded.
    var currentBuddyID: String { buddy?.id ?? "—" }

    func setBuddy(_ manifest: BuddyManifest) {
        buddy = manifest
        applyState(animated: false)
    }

    /// How many agents are running. Redraws only when the number changes.
    /// Change the interface language. Redraws immediately: a language picker
    /// that needs a restart is a language picker people distrust.
    func setLanguage(_ strings: Strings, locale: Locale) {
        self.l10n = strings
        self.locale = locale
        applyState(animated: false)
    }

    /// Latest usage reading. Only redraws while the panel is open.
    /// How coarse the buddy's pixels are.
    func setPixelSize(_ size: Double) {
        guard size != pixelSize else { return }
        pixelSize = size
        rebuildContent()
    }

    /// The three preferences the panel renders.
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

    /// Say how the last jump went, or clear the message.
    ///
    /// Only redrawn while the panel is open — a note nobody can see is a
    /// wakeup spent on nothing.
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

    /// Full session list, for the expanded panel.
    ///
    /// Only redraws while the panel is open: the collapsed pill shows a count,
    /// and rebuilding a list nobody can see on every 2 s refresh is waste.
    func setSessions(_ list: [AgentSession]) {
        guard list != sessions else { return }
        sessions = list
        if state == .panel { rebuildContent() }
    }

    func setSessionCount(_ count: Int) {
        guard count != sessionCount else { return }
        sessionCount = count
        // The counter's width feeds the pill's width, so the frame has to
        // follow — `×9` and `×10` are not the same size.
        applyState(animated: false)
    }

    /// Update the face. Cheap enough to call on every session snapshot.
    func setExpression(_ next: BuddyExpression) {
        guard next != expression else { return }
        expression = next
        budget.update(isVisible: state.isVisible, isBusy: next != .sleeping && next != .idle)
        rebuildContent()
    }

    /// Show an alert in the pill for a few seconds, then return to normal.
    ///
    /// Never interrupts an open panel: if the user has the panel deployed they
    /// are already looking, and shrinking it under them to show a badge would be
    /// worse than saying nothing.
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
        // host fills the window, so its coordinates are the window's.
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
