import AppKit
import SwiftUI
import VibeBuddyKit

/// Its own window, not a taller pill. The pill's height is what its hover, the buddy's
/// seat and the face's click target are measured against; growing it for a tongue
/// would move all three, and its click strip would swallow a pill-wide band under the
/// menu bar. This window absorbs exactly the tongue and nothing else.
@MainActor
final class AlertTongueWindow: NSPanel {
    /// A click on the tongue.
    var onClick: () -> Void = {}

    private let host = TongueHostView()

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 120, height: AlertTongueView.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = host
        host.onClick = { [weak self] in self?.onClick() }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Hung from `top`, centred on `centreX`, no wider than `maxWidth` — screen points.
    func show(alert: SessionAlert, others: Int, colour: Color,
              centreX: CGFloat, top: CGFloat, maxWidth: CGFloat) {
        host.set(AlertTongueView(alert: alert, others: others, colour: colour))
        let natural = host.fittingWidth
        // Never narrower than a proper slab under the notch: the slants need room, and
        // a short project name should not make the tongue a stub.
        let width = min(max(natural, 170), maxWidth)
        let height = AlertTongueView.height
        setFrame(CGRect(x: (centreX - width / 2).rounded(), y: top - height,
                        width: width, height: height), display: true)
        // Above the pill, so its top covers the pill's bottom edge where they join.
        orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
        // Dropped so the next showing is a new view, and slides down again.
        host.reset()
    }
}

/// Takes every click inside its bounds for itself: the SwiftUI content is a picture,
/// and the whole tongue is one button.
private final class TongueHostView: NSView {
    var onClick: () -> Void = {}
    private var hosting: NSHostingView<AlertTongueView>?

    var fittingWidth: CGFloat { hosting?.fittingSize.width ?? 0 }

    func reset() {
        hosting?.removeFromSuperview()
        hosting = nil
    }

    func set(_ view: AlertTongueView) {
        if let hosting {
            hosting.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.autoresizingMask = [.width, .height]
            hosting.frame = bounds
            addSubview(hosting)
            self.hosting = hosting
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // The app is an accessory and never active: without this the first click only
    // brings the window forward.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick()
    }
}
