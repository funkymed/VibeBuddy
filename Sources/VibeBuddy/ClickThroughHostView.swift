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
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

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
