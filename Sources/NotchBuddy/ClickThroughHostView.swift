import AppKit
import SwiftUI

/// Hosts SwiftUI and filters hit-tests so clicks on transparent parts of the
/// window reach whatever is underneath — the menu bar, in practice.
///
/// The window is deliberately wider than the pill it draws, so the
/// collapsed↔expanded transition doesn't jump horizontally. Without this filter
/// the invisible margins would swallow menu-bar clicks: the user would click the
/// clock and nothing would happen. The reference implementation hit this exact
/// bug (its comment cites the issue) and solved it the same way.
final class ClickThroughHostView<Content: View>: NSView {

    /// The region of the window that should absorb clicks.
    enum HitRegion: Equatable {
        /// Absorb nothing — the window is effectively not there.
        case none
        /// Absorb everything: the expanded panel really does fill its frame.
        case full
        /// Absorb a horizontal strip of `width`, centred, shifted by `offsetX`
        /// so the region tracks the pill when SwiftUI draws it off-centre.
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

    /// Track hover on the drawn region only.
    ///
    /// The objection to `NSTrackingArea` was that it follows the *window*, which
    /// is far wider than the pill — so it would fire across the transparent
    /// margins. That is only true of the convenience that tracks `bounds`.
    /// `NSTrackingArea(rect:)` takes an explicit rect, and `absorbingRect` is
    /// exactly the region that draws.
    ///
    /// Being event-driven, this costs **nothing** while the pointer is still —
    /// unlike polling `NSEvent.mouseLocation`, which turned out to be a
    /// window-server round trip rather than the cheap local read it looks like.
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

    /// Rect currently absorbing clicks, in view coordinates.
    var absorbingRect: CGRect {
        switch hitRegion {
        case .none:
            return .zero
        case .full:
            return bounds
        case let .strip(width, offsetX):
            return CGRect(
                x: (bounds.width - width) / 2 + offsetX,
                y: 0,
                width: width,
                height: bounds.height
            )
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitRegion != .none, absorbingRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
