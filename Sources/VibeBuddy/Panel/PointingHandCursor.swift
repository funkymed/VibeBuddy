import AppKit
import SwiftUI

/// Rectangles that deserve a pointing hand, in screen coordinates.
///
/// The panel is a `.nonactivatingPanel` whose `canBecomeKey` is `false`, and
/// that rules out every convenient mechanism: AppKit consults cursor rects for
/// the key window only, and a `.cursorUpdate` tracking area on a SwiftUI-hosted
/// view never fired here (verified with a live trace: zero calls while hover
/// fired normally).
///
/// What does work is the panel's own event path. SwiftUI marks the zones, the
/// host view sets the cursor when a mouse-moved event says the pointer is in
/// one of them — after AppKit's own reset, so nothing fights back.
@MainActor
final class CursorZones {

    static let shared = CursorZones()

    /// The views that want a hand, **not** the rectangles they occupied.
    ///
    /// It used to hold screen rects, published when a view was added, resized
    /// or moved between superviews. That was true for a window that never
    /// changed shape. This panel now resizes itself to whatever it is showing
    /// — 292 pt for a shell command, 460 for a plan — and it animates there, so
    /// every stored rect was stale from the first frame of the resize until
    /// something happened to republish it. The pointer flickered between hand
    /// and arrow because the zones were describing a window that no longer
    /// existed.
    ///
    /// Asking the view where it is, at the moment the question is asked, cannot
    /// go stale. It costs a coordinate conversion per mouse-moved event over a
    /// handful of views, against a resize that could not be caught reliably.
    private var owners: [ObjectIdentifier: WeakView] = [:]

    private struct WeakView { weak var view: HandCursorView? }

    func register(_ view: HandCursorView) {
        owners[ObjectIdentifier(view)] = WeakView(view: view)
    }

    func unregister(_ view: HandCursorView) {
        owners.removeValue(forKey: ObjectIdentifier(view))
        // **No « false » on the way out.**
        //
        // It looked prudent — a zone that vanishes under the pointer should say
        // so — and it was the opposite. Lighting a control changes SwiftUI
        // state, SwiftUI may rebuild the overlay that carries this view, and a
        // rebuild unregisters the old one: the hover was cancelled by its own
        // consequence, one frame after it arrived. Highlight, flicker, nothing.
        //
        // A zone that really is gone stops being consulted, and the control it
        // belonged to is gone with it.
    }

    /// Tells every zone whether it holds the pointer, and answers whether any
    /// of them does.
    ///
    /// **This is also where hover comes from.** SwiftUI's `.onHover` was doing
    /// that job and did it unevenly: it rides tracking areas of its own, in a
    /// window that is only key while deployed, and sweeping quickly across a
    /// list dropped enters and exits — « parfois ça ne marche pas ». The panel
    /// already receives every mouse-moved event reliably, because that is what
    /// places the cursor. One source of movement, one answer: a control is
    /// hovered exactly when the pointer is in its zone.
    /// - Parameter windowPoint: the position **carried by the event being
    ///   handled**, in its window's coordinates — `event.locationInWindow`.
    ///
    ///   Not `NSEvent.mouseLocation`. That reads where the pointer is *now*,
    ///   and AppKit coalesces mouse-moved events: by the time one is handled
    ///   the pointer has moved on, often into the six-point gap between two
    ///   controls. Slid slowly the two agree and everything works; slid quickly
    ///   the test lands in the gap and nothing lights — exactly « il faut le
    ///   faire lentement ».
    @discardableResult
    func update(forWindowPoint windowPoint: NSPoint, in window: NSWindow) -> Bool {
        var dead: [ObjectIdentifier] = []
        var hit = false
        for (key, box) in owners {
            guard let view = box.view, view.window === window, !view.bounds.isEmpty else {
                if box.view == nil { dead.append(key) }
                continue
            }
            let inside = view.convert(windowPoint, from: nil).isWithin(view.bounds)
            view.setHovered(inside)
            if inside { hit = true }
        }
        for key in dead { owners.removeValue(forKey: key) }
        return hit
    }

    /// Whether a **screen** point falls in a zone. Used only to choose the
    /// cursor, where « where the pointer is now » is the right question.
    func contains(_ point: NSPoint) -> Bool {
        owners.values.contains { box in
            guard let view = box.view, let window = view.window, !view.bounds.isEmpty
            else { return false }
            let inWindow = window.convertPoint(fromScreen: point)
            return view.convert(inWindow, from: nil).isWithin(view.bounds)
        }
    }

    /// Called when the pointer leaves the panel entirely.
    func clearAll() {
        for box in owners.values { box.view?.setHovered(false) }
    }
}

private extension NSPoint {
    /// `NSRect.contains` on a point that a conversion landed exactly on an edge
    /// of is a coin toss; a zone that ends one point short of where the button
    /// is drawn is a row that loses the hand at its own border.
    func isWithin(_ rect: NSRect) -> Bool {
        x >= rect.minX && x <= rect.maxX && y >= rect.minY && y <= rect.maxY
    }
}

/// Publishes its own frame as a hand zone, and nothing else.
@MainActor
final class HandCursorView: NSView {

    var isEnabled = true { didSet { publish() } }
    /// Reported outward when the pointer enters or leaves this zone. Fed by
    /// `CursorZones.update(for:)`, which runs on the panel's own mouse events.
    var onHover: (Bool) -> Void = { _ in }
    private var hovered = false

    func setHovered(_ inside: Bool) {
        guard inside != hovered else { return }
        hovered = inside
        onHover(inside)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        publish()
    }

    // Transparent to clicks: this view carries no behaviour of its own.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Registration only. Where this view *is* gets asked at the moment the
    /// pointer moves, so nothing here has to fire on a resize.
    private func publish() {
        if isEnabled, window != nil {
            CursorZones.shared.register(self)
        } else {
            CursorZones.shared.unregister(self)
        }
    }

    override func removeFromSuperview() {
        CursorZones.shared.unregister(self)
        super.removeFromSuperview()
    }

    deinit { MainActor.assumeIsolated { CursorZones.shared.unregister(self) } }
}

private struct HandCursorLayer: NSViewRepresentable {
    let isEnabled: Bool
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HandCursorView {
        let view = HandCursorView()
        view.isEnabled = isEnabled
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: HandCursorView, context: Context) {
        view.isEnabled = isEnabled
        view.onHover = onHover
    }
}

struct PointingHandCursor: ViewModifier {

    /// Only clickable things get the hand. A dead session is still a row, and a
    /// disabled button would promise a click that does nothing.
    let isEnabled: Bool
    /// Reported outward so a caller that already tracks hover — the row's own
    /// highlight — does not install a second handler for the same pointer.
    var onHoverChange: (Bool) -> Void = { _ in }

    func body(content: Content) -> some View {
        content
            // Hover and cursor come from the same layer, so they can never
            // disagree — and both ride the panel's own events rather than
            // SwiftUI's tracking areas. See `CursorZones.update(for:)`.
            .overlay {
                HandCursorLayer(isEnabled: isEnabled, onHover: onHoverChange)
            }
    }
}

extension View {
    /// A hand over this view while `isEnabled`, plus the hover state if wanted.
    func pointingHandCursor(
        _ isEnabled: Bool = true,
        onHoverChange: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(PointingHandCursor(isEnabled: isEnabled, onHoverChange: onHoverChange))
    }
}
