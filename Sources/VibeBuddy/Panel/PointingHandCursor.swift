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
    private var zones: [ObjectIdentifier: NSRect] = [:]

    func set(_ rect: NSRect?, for owner: AnyObject) {
        let key = ObjectIdentifier(owner)
        if let rect, !rect.isEmpty { zones[key] = rect } else { zones.removeValue(forKey: key) }
    }

    func contains(_ point: NSPoint) -> Bool {
        zones.values.contains { $0.contains(point) }
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        publish()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        publish()
    }

    // Transparent to clicks: this view carries no behaviour of its own.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func publish() {
        guard isEnabled, let window, !bounds.isEmpty else {
            CursorZones.shared.set(nil, for: self)
            return
        }
        let inWindow = convert(bounds, to: nil)
        CursorZones.shared.set(window.convertToScreen(inWindow), for: self)
    }

    override func removeFromSuperview() {
        CursorZones.shared.set(nil, for: self)
        super.removeFromSuperview()
    }
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
