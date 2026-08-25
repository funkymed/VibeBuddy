import AppKit
import SwiftUI

/// Rectangles that deserve a pointing hand, in screen coordinates.
@MainActor
final class CursorZones {
    static let shared = CursorZones()

    /// The views that want a hand, not the rectangles they occupied. This panel now
    /// resizes itself to whatever it is showing — 292 pt for a shell command, 460 for a
    /// plan — and it animates there, so every stored rect was stale from the first frame
    /// of the resize until something happened to republish it.
    private var owners: [ObjectIdentifier: WeakView] = [:]

    private struct WeakView { weak var view: HandCursorView? }

    func register(_ view: HandCursorView) {
        owners[ObjectIdentifier(view)] = WeakView(view: view)
    }

    func unregister(_ view: HandCursorView) {
        owners.removeValue(forKey: ObjectIdentifier(view))
        // No « false » on the way out.
    }

    /// Tells every zone whether it holds the pointer, and answers whether any of them
    /// does.
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

    /// Whether a screen point falls in a zone.
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
    /// `NSRect.contains` on a point that a conversion landed exactly on an edge of is a
    /// coin toss; a zone that ends one point short of where the button is drawn is a row
    /// that loses the hand at its own border.
    func isWithin(_ rect: NSRect) -> Bool {
        x >= rect.minX && x <= rect.maxX && y >= rect.minY && y <= rect.maxY
    }
}

/// Publishes its own frame as a hand zone, and nothing else.
@MainActor
final class HandCursorView: NSView {
    var isEnabled = true { didSet { publish() } }
    /// Reported outward when the pointer enters or leaves this zone.
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

    /// Registration only.
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
    /// Only clickable things get the hand.
    let isEnabled: Bool
    /// Reported outward so a caller that already tracks hover — the row's own highlight
    /// — does not install a second handler for the same pointer.
    var onHoverChange: (Bool) -> Void = { _ in }

    func body(content: Content) -> some View {
        content
            // Hover and cursor come from the same layer, so they can never disagree —
            // and both ride the panel's own events rather than SwiftUI's tracking
            // areas.
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
