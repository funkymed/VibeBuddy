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

    private struct WeakView { weak var view: NSView? }

    func register(_ view: NSView) { owners[ObjectIdentifier(view)] = WeakView(view: view) }

    func unregister(_ view: NSView) { owners.removeValue(forKey: ObjectIdentifier(view)) }

    /// Whether a screen point falls in a live zone.
    func contains(_ point: NSPoint) -> Bool {
        var dead: [ObjectIdentifier] = []
        var hit = false
        for (key, box) in owners {
            guard let view = box.view, let window = view.window, !view.bounds.isEmpty else {
                dead.append(key)
                continue
            }
            let inWindow = window.convertPoint(fromScreen: point)
            if view.convert(inWindow, from: nil).isWithin(view.bounds) { hit = true }
        }
        for key in dead { owners.removeValue(forKey: key) }
        return hit
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
private final class HandCursorView: NSView {

    var isEnabled = true { didSet { publish() } }

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

    func makeNSView(context: Context) -> NSView {
        let view = HandCursorView()
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? HandCursorView)?.isEnabled = isEnabled
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
            .overlay { HandCursorLayer(isEnabled: isEnabled) }
            .onHover(perform: onHoverChange)
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
