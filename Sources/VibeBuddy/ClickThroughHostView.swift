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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // **Nobody else gets to set a cursor in this window.**
        //
        // AppKit rebuilds cursor rects on every mouse-moved event and applies
        // whatever it finds — including the ones SwiftUI installs for its own
        // controls and for selectable text. Ours was set correctly (traced:
        // `zones=7 inZone=true`, hand requested) and then immediately replaced,
        // which is why the hand never appeared for more than a frame.
        //
        // Turning the mechanism off for this window leaves exactly one writer:
        // `applyCursor`.
        window?.disableCursorRects()
    }

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
    ///
    /// **On the next turn of the run loop, never inline.** `refreshTracking` is
    /// reached from the panel setting `hitRegion` in the middle of applying a
    /// state change; reporting hover from there re-entered that same state
    /// change through the hover handler, and the outer call then finished with
    /// values it had computed for the state it was leaving. What you saw was an
    /// all-black panel: the shape sized for the panel, the pill content skipped
    /// because the state said panel, and the panel content skipped because the
    /// stale outer call had just cleared the reveal flag.
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
        scheduleCursor()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        scheduleCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        scheduleCursor()
    }


    /// **The one place a cursor is chosen, and it runs last.**
    ///
    /// Three parties want this pointer: us, SwiftUI's own `Button` tracking
    /// areas, and — the one that was actually doing the damage — the I-beam
    /// that `.textSelection(.enabled)` installs over the question and the diff.
    /// They all act while the event is being delivered, in an order nothing
    /// here controls, which is exactly what « le pointeur change tout le temps »
    /// looks like.
    ///
    /// Deferring by one turn of the run loop settles it: everyone else has had
    /// their say by then, and the last writer wins. It is also why this cannot
    /// be a cursor rect or a `.cursorUpdate` area — neither reaches a window
    /// that never becomes key, and this panel never does.
    private func scheduleCursor() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.applyCursor() }
        }
    }

    private func applyCursor() {
        guard window != nil else { return }
        let wanted: NSCursor = CursorZones.shared.contains(NSEvent.mouseLocation)
            ? .pointingHand : .arrow
        // **Compare against what is on screen, not against what we last set.**
        //
        // Remembering our own last value looked like the obvious way to avoid
        // re-setting the same cursor on every event — and it is what broke it:
        // the frontmost application resets the cursor whenever the pointer
        // moves over it, so ours is wiped without us hearing about it, and a
        // « we already put the hand there » flag then guarantees we never put
        // it back. The hand appeared for one frame and never again.
        //
        // `currentSystem` is what is actually displayed, so this re-asserts
        // exactly when something else has taken it, and stays silent otherwise.
        guard NSCursor.currentSystem !== wanted else { return }
        wanted.set()
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
