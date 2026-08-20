import AppKit
import SwiftUI

/// Hosts SwiftUI and filters hit-tests so clicks on the window's transparent
/// margins reach the menu bar. Without it, clicking the clock does nothing.
final class ClickThroughHostView<Content: View>: NSView {

    /// The region of the window that should absorb clicks.
    enum HitRegion: Equatable {
        case none
        case full
        /// Horizontal strip of `width`, centred, shifted by `offsetX` so the
        /// region tracks the pill when SwiftUI draws it off-centre.
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

    /// Do not remove: an `NSTrackingArea` rect is in view coordinates and does
    /// not follow a resize, and `layout()` is not called for a plain frame
    /// change. A strip built while the window was 460 tall kept arming hover
    /// after it shrank to 38 — see RFC-002, « Notes d'implémentation ».
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshTracking()
    }

    /// Rebuild the tracking rect against the current bounds. The panel needs it
    /// once the frame has settled: the region is chosen before the resize.
    func refreshTrackingNow() { refreshTracking() }

    private func refreshTracking() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        let rect = absorbingRect
        guard hitRegion != .none, !rect.isEmpty else { return }
        let area = NSTrackingArea(
            rect: rect,
            // `.activeAlways` matters: the app is an accessory and never
            // becomes active, so anything gated on active state never fires.
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        tracking = area

        // A tracking area sends no enter event for a pointer that was already
        // inside when it was created. The region is rebuilt on every state
        // change and every resize, so a still pointer gets no event at all and
        // the panel waits for the 5 s fallback poll instead of opening.
        reportPointerIfInside(rect)
    }

    /// Report hover for a pointer that is already inside `rect`, in view
    /// coordinates.
    private func reportPointerIfInside(_ rect: CGRect) {
        guard let window else { return }
        let onScreen = NSEvent.mouseLocation
        let inWindow = window.convertPoint(fromScreen: onScreen)
        let inView = convert(inWindow, from: nil)
        guard rect.contains(inView) else { return }
        onHoverChange?(true)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
        applyCursor()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        applyCursor()
    }

    /// The hand over a zone SwiftUI marked, the arrow anywhere else.
    ///
    /// Set from the panel's own event path rather than from a cursor rect or a
    /// `.cursorUpdate` area: neither reaches a window that never becomes key,
    /// which this panel never does. Setting here runs after AppKit's own reset
    /// for the same event, so there is nothing to fight.
    private func applyCursor() {
        let pointer = NSEvent.mouseLocation
        if CursorZones.shared.contains(pointer) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// Rect currently absorbing clicks, in view coordinates. Clamped to
    /// `bounds`: a wider strip would arm the hover from outside the window.
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
