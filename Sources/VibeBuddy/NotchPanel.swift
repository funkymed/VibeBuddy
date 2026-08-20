import AppKit
import SwiftUI
import VibeBuddyKit

/// The window. Geometry arithmetic lives in `NotchFrameSolver`, where it is
/// testable without a display. One state, exactly one frame per transition.
@MainActor
final class NotchPanel: NSPanel {

    static let panelSize = CGSize(width: 560, height: 460)
    /// Kept at panel width even in pill state, so the transition never jumps
    /// horizontally. `ClickThroughHostView` keeps the margins click-through.
    static let carrierWidth: CGFloat = 560

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
    /// Panel-facing preferences (RFC-010), held as plain values: observing the
    /// models would re-evaluate the view on every preference write.
    private var pixelSize: Double = Double(BuddyView.defaultPixelSize)
    private var groupByDirectory = true
    private var jumpOnClick = true
    private var showUsage = true

    /// Suppresses hover while another surface of ours owns the screen.
    ///
    /// Do not pin the panel open over the settings window: `.floating` (3) is
    /// below `.statusBar` (25), so the panel covers what it just opened.
    /// See RFC-002, « Notes d'implémentation ».
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

    /// Do not allow key: `.nonactivatingPanel` stops activation but not key
    /// theft from the terminal underneath. Cost: no keyboard shortcuts inside.
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
        let size = state == .panel ? Self.panelSize : pillSize
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

    private func applyState(animated: Bool = true) {
        if applying { needsReapply = true; return }
        applying = true
        defer {
            applying = false
            if needsReapply {
                needsReapply = false
                applyState(animated: animated)
            }
        }

        // Shadowed once so the whole body agrees with itself even if something
        // it calls changes the state underneath it.
        let state = self.state
        frameGeneration += 1
        let generation = frameGeneration
        let size = state == .panel ? Self.panelSize : pillSize
        let carrier = CGSize(width: Self.carrierWidth, height: size.height)

        // Destination region up front: interpolating it drops the pointer out
        // of the growing panel and collapses it mid-open.
        host.hitRegion = hitRegion(for: state)

        if state.isVisible { orderFrontRegardless() }

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
        hover.pillRect = pillScreenRect
        hover.setActive(state.isVisible)
        budget.update(isVisible: state.isVisible, isBusy: state == .panel)
    }
    /// Hover opens the panel from `.pill` **and from `.speech`**.
    ///
    /// An alert used to lock the pill for its four seconds: reaching for a
    /// notification and having it refuse to open is the opposite of what the
    /// notification is for. Opening dismisses the bubble, the panel says the
    /// same thing with more detail.
    private func hoverChanged(_ hovering: Bool) {
        if hovering, state == .pill || state == .speech {
            alertDismissal?.cancel()
            currentAlert = nil
            state = .panel
        } else if !hovering, state == .panel {
            state = .pill
        }
    }



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
    private var pillScreenRect: CGRect {
        let f = frame
        let w = state == .panel ? Self.panelSize.width : pillSize.width
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
                       onJump: onJump, jumpNote: jumpNote,
                       pixelSize: pixelSize, groupByDirectory: groupByDirectory,
                       jumpOnClick: jumpOnClick, showUsage: showUsage)
    }

    private func rebuildContent() {
        host.hosting.rootView = shellView
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

    func setPixelSize(_ size: Double) {
        guard size != pixelSize else { return }
        pixelSize = size
        rebuildContent()
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
        if state == .panel { rebuildContent() }
    }

    func setSessionCount(_ count: Int) {
        guard count != sessionCount else { return }
        sessionCount = count
        // The counter feeds the pill width: `×9` and `×10` differ.
        applyState(animated: false)
    }

    func setExpression(_ next: BuddyExpression) {
        guard next != expression else { return }
        expression = next
        budget.update(isVisible: state.isVisible, isBusy: next != .sleeping && next != .idle)
        rebuildContent()
    }

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
