import AppKit
import SwiftUI

/// Hosts SwiftUI and filters hit-tests so clicks on the window's transparent margins
/// reach the menu bar.
final class ClickThroughHostView<Content: View>: NSView {
    /// The region of the window that should absorb clicks.
    enum HitRegion: Equatable {
        case none
        case full
        /// Horizontal strip of `width`, centred, shifted by `offsetX` so the region
        /// tracks the pill when SwiftUI draws it off-centre.
        case strip(width: CGFloat, offsetX: CGFloat)
    }

    let hosting: NSHostingView<Content>
    var hitRegion: HitRegion = .none {
        didSet { if hitRegion != oldValue { refreshTracking() } }
    }

    /// Fired when the pointer enters or leaves the region that actually draws.
    var onHoverChange: ((Bool) -> Void)?

    private var tracking: NSTrackingArea?

    init(rootView: Content) {
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        refreshTracking()
    }

    /// Do not remove: an `NSTrackingArea` rect is in view coordinates and does not
    /// follow a resize, and `layout()` is not called for a plain frame change.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Nobody else gets to set a cursor in this window.
        window?.disableCursorRects()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshTracking()
    }

    /// Rebuild the tracking rect against the current bounds.
    func refreshTrackingNow() { refreshTracking() }

    private func refreshTracking() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        let rect = absorbingRect
        guard hitRegion != .none, !rect.isEmpty else { return }
        let area = NSTrackingArea(
            rect: rect,
            // `.activeAlways` matters: the app is an accessory and never becomes
            // active, so anything gated on active state never fires.
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        tracking = area

        // A tracking area sends no enter event for a pointer that was already inside
        // when it was created. The region is rebuilt on every state change and every
        // resize, so a still pointer gets no event at all and the panel waits for the 5
        // s fallback poll instead of opening.
        reportPointerIfInside(rect)
    }

    /// Report hover for a pointer that is already inside `rect`, in view coordinates.
    private func reportPointerIfInside(_ rect: CGRect) {
        guard let window else { return }
        let onScreen = NSEvent.mouseLocation
        let inWindow = window.convertPoint(fromScreen: onScreen)
        let inView = convert(inWindow, from: nil)
        guard rect.contains(inView) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.absorbingRect.contains(
                self.convert(
                    self.window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero,
                    from: nil))
            else { return }
            self.onHoverChange?(true)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
        updateHover(with: event)
        scheduleCursor()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
        // Leaving the panel leaves every zone in it.
        CursorZones.shared.clearAll()
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        // Hover now, cursor next turn. The deferral exists to win the cursor back
        // from whoever set it during this event — it buys nothing for hover, and costs
        // it a run-loop turn on every movement.
        updateHover(with: event)
        scheduleCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        updateHover(with: event)
        scheduleCursor()
    }

    /// The one place a cursor is chosen, and it runs last.
    private func updateHover(with event: NSEvent) {
        guard let window else { return }
        CursorZones.shared.update(forWindowPoint: event.locationInWindow, in: window)
    }

    private func scheduleCursor() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.applyCursor() }
        }
    }

    private func applyCursor() {
        guard window != nil else { return }
        // Updates every zone's hover state on the way, which is where the controls
        // learn that the pointer arrived or left.
        let wanted: NSCursor = CursorZones.shared.contains(NSEvent.mouseLocation)
            ? .pointingHand : .arrow
        // Compare against what is on screen, not against what we last set.
        guard NSCursor.currentSystem !== wanted else { return }
        wanted.set()
    }

    /// Rect currently absorbing clicks, in view coordinates.
    var absorbingRect: CGRect {
        switch hitRegion {
        case .none:
            return .zero
        case .full:
            return bounds
        case let .strip(width, offsetX):
            let clamped = min(width, bounds.width)
            return CGRect(
                x: (bounds.width - clamped) / 2 + offsetX,
                y: 0,
                width: clamped,
                height: bounds.height
            ).intersection(bounds)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitRegion != .none, absorbingRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
