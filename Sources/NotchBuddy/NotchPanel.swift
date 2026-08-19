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
            guard let self else { return }
            if hovering, state == .pill { state = .panel }
            else if !hovering, state == .panel { state = .pill }
        }

        hover.onChange = { [weak self] hovering in
            guard let self else { return }
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
    var pillSize: CGSize {
        guard let geometry else { return CGSize(width: 300, height: 32) }
        return NotchFrameSolver.pillSize(geometry: geometry)
    }

    private func applyState(animated: Bool = true) {
        let size = state == .panel ? Self.panelSize : pillSize
        let carrier = CGSize(width: Self.carrierWidth, height: size.height)

        // Set the hit region to the destination up front. Interpolating it would
        // make the pointer fall out of the panel mid-grow and immediately
        // trigger a collapse — the panel would flicker instead of opening.
        host.hitRegion = switch state {
        case .hidden: .none
        case .panel:  .full
        case .pill, .speech: .strip(width: size.width, offsetX: 0)
        }

        if state.isVisible { orderFrontRegardless() }
        // Swap the content *before* the frame moves, so the shape morphs with
        // the window instead of snapping at the end of the animation.
        rebuildContent()

        let target = geometry.map {
            NotchFrameSolver.frame(size: carrier, geometry: $0, fraction: anchorFraction)
        }

        // Respect the system setting. Someone who asked for less motion did not
        // ask for it only in other people's apps.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion, state != .hidden, frame.size != carrier else {
            if let target { setFrame(target, display: true, animate: false) }
            metrics.drawnWidth = size.width
            alphaValue = state.isVisible ? 1 : 0
            if !state.isVisible { orderOut(nil) }
            finishStateChange()
            return
        }

        growTogether(
            to: target,
            drawnWidth: size.width,
            growing: carrier.height > frame.height
        )
    }

    /// Both axes at once.
    ///
    /// The width lives in SwiftUI and the height on the `NSWindow`, so this is
    /// two animation engines that have to land together: same duration, same
    /// curve, started in the same turn of the run loop. Any drift between them
    /// shows up as the shape stretching before it settles.
    private func growTogether(to target: CGRect?, drawnWidth: CGFloat, growing: Bool) {
        let duration = growing ? PanelTiming.expand : PanelTiming.collapse

        withAnimation(.easeOut(duration: duration)) {
            metrics.drawnWidth = drawnWidth
        }
        alphaValue = 1

        guard let target else { finishStateChange(); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = Self.expandCurve
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishStateChange() }
        }
    }

    /// Everything that can only be settled once the frame has stopped moving —
    /// the hover rect in particular, which is read from the live frame.
    private func finishStateChange() {
        hover.pillRect = pillScreenRect
        hover.setActive(state.isVisible)
        budget.update(isVisible: state.isVisible, isBusy: state == .panel)
    }

    /// Screen-space rect of the visible pill, which is narrower than the window.
    private var pillScreenRect: CGRect {
        let f = frame
        let w = state == .panel ? Self.panelSize.width : pillSize.width
        return CGRect(x: f.midX - w / 2, y: f.minY, width: w, height: f.height)
    }

    private func rebuildContent() {
        host.hosting.rootView = AnyView(
            NotchShellView(state: state, geometry: geometry, budget: budget, metrics: metrics)
        )
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
