import AppKit
import NotchBuddyKit

/// Tracks whether the pointer is over the pill.
///
/// # Why this polls
///
/// A global `NSEvent` monitor would be event-driven and cost nothing while the
/// mouse is still. It also needs an Input Monitoring grant, and RFC-011 rules
/// out permission-gated APIs for v1 — the whole point of accepting a self-signed
/// build was to have nothing to revoke. An `NSTrackingArea` cannot help either:
/// it tracks the *window*, and this window is far wider than the pill it draws,
/// so it would fire across the transparent margins.
///
/// # It is now a safety net, not the mechanism
///
/// `ClickThroughHostView` installs an `NSTrackingArea` over the drawn rect, so
/// hover is event-driven and instantaneous. This poll stays behind it at a slow
/// cadence, for the cases a tracking area genuinely misses: a pointer warped by
/// a hotkey or by `CGWarpMouseCursorPosition` generates no enter event at all.
///
/// # Why the fast poll was removed
///
/// The first version was cleverer: 1 Hz normally, promoted to 10 Hz only once
/// the pointer entered a strip near the top of the screen. It was measurably
/// pointless and perceptibly bad.
///
/// Measured: 10 Hz costs **0.036 idle wakeups per second** — 1.8 % of the
/// resting budget of two per second. The cadence fires ten times a second, but
/// the 25 % leeway lets the kernel coalesce those firings with timers it was
/// going to service anyway, and coalesced wakeups are close to free.
///
/// The two-stage version bought that 0.036 back and paid for it with **up to a
/// full second of latency**: a fast cursor can cross the promotion strip between
/// two 1 Hz polls, so the hover is only noticed on the next coarse tick. The
/// panel opened late, and the delay was the first thing anyone noticed.
///
/// Polling at 10 Hz fixed the latency and cost **6.3 idle wakeups per second** —
/// three times the resting budget. The earlier figure of 0.036/s was measured
/// with an empty closure and was therefore meaningless: the cost is not the
/// timer, it is `NSEvent.mouseLocation`, which despite appearances is a
/// window-server round trip and not a local read.
///
/// Hence the tracking area, and hence this poll dropping to `.idle`.
@MainActor
final class HoverProbe {

    /// Hysteresis margin. Entering uses the bare pill rect, leaving uses the
    /// rect grown by this much.
    ///
    /// Without it, a pointer resting exactly on the boundary toggles on every
    /// poll as sub-pixel jitter carries it across, and the panel flickers open
    /// and shut. The reference implementation documents the same fix.
    private static let exitMargin: CGFloat = 8

    private let wake: WakeCoordinator
    private let id = "hover"

    /// Rect of the visible pill in screen coordinates. Set by the panel; empty
    /// means nothing to hover.
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

    /// Called when the pill appears or disappears. Stopping is the point: the
    /// reference implementation never stops anything, and polls at 10 Hz with
    /// the lid shut.
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
