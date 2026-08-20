import AppKit
import VibeBuddyKit

/// Safety net behind the event-driven hover of `ClickThroughHostView`: a pointer
/// warped by a hotkey emits no enter event. See RFC-002, « Notes d'implémentation ».
///
/// Do not bench with an empty closure: 10 Hz measured 0.036 idle wakeups/s that
/// way, 6.3/s with the real body, against a resting budget of 2/s. The cost is
/// `NSEvent.mouseLocation` — a window-server round trip, not a local read.
@MainActor
final class HoverProbe {

    /// Hysteresis: entering uses the bare pill rect, leaving uses it grown by
    /// this much. Without it, sub-pixel jitter on the boundary flickers the
    /// panel open and shut on every poll.
    private static let exitMargin: CGFloat = 8

    private let wake: WakeCoordinator
    private let id = "hover"

    /// Visible pill in screen coordinates. Empty means nothing to hover.
    var pillRect: CGRect = .zero {
        didSet { if pillRect != oldValue { evaluate() } }
    }

    private(set) var isHovering = false {
        didSet { if isHovering != oldValue { onChange?(isHovering) } }
    }

    var onChange: ((Bool) -> Void)?

    private var isRunning = false

    init(wake: WakeCoordinator) {
        self.wake = wake
    }

    /// Called when the pill appears or disappears. Stopping is the point.
    func setActive(_ active: Bool) {
        guard active != isRunning else { return }
        isRunning = active
        if active {
            wake.register(id: id, cadence: .idle) { [weak self] in self?.evaluate() }
            evaluate()
        } else {
            wake.unregister(id: id)
            isHovering = false
        }
    }

    private func evaluate() {
        guard isRunning, !pillRect.isEmpty else { return }
        let point = NSEvent.mouseLocation

        let rect = isHovering ? pillRect.insetBy(dx: -Self.exitMargin, dy: -Self.exitMargin) : pillRect
        isHovering = rect.contains(point)
    }
}
