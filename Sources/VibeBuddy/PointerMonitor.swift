import AppKit
import VibeBuddyKit

/// Feeds `PointerGaze` with where the mouse is.
///
/// **Why a monitor and not a poll.** `HoverProbe` polls, and its own note says
/// what that costs: `NSEvent.mouseLocation` is a window-server round trip, and
/// at 10 Hz it measured 6,3 wakeups/s against a resting budget of 2. Following
/// the pointer needs it at three times that rate. A monitor inverts the cost —
/// it is silent while the pointer is still, which is the case the budget is
/// written for, and it only fires while the user is already moving the mouse.
///
/// No Accessibility permission is involved: that is required for keyboard
/// monitors, not for mouse ones. The v1 rule against AX APIs holds.
@MainActor
final class PointerMonitor {

    /// Floor between two samples. Mouse events arrive at the display's rate on
    /// a trackpad and faster on some mice; the face redraws at 30 Hz at best,
    /// so anything above that is work thrown away.
    private static let minimumInterval: TimeInterval = 1.0 / 30

    private let gaze: PointerGaze
    private var global: Any?
    private var local: Any?
    private var lastSample = Date.distantPast

    init(gaze: PointerGaze) {
        self.gaze = gaze
    }

    var isRunning: Bool { global != nil }

    func setActive(_ active: Bool) {
        guard active != isRunning else { return }
        active ? start() : stop()
    }

    private func start() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.sample(event) }
        }
        // The global monitor does not see events delivered to our own app, and
        // the panel is exactly what the pointer is over when it comes to say
        // hello. Local monitors must return the event or they swallow it.
        local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.sample(event) }
            return event
        }
    }

    private func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }

    private func sample(_ event: NSEvent) {
        let now = Date()
        guard now.timeIntervalSince(lastSample) >= Self.minimumInterval else { return }
        lastSample = now
        // `NSEvent.mouseLocation` rather than the event's own location: a global
        // monitor's event carries window coordinates of a window that is not
        // ours. This one is already in screen space, and reading it inside an
        // event we were handed anyway costs no extra round trip.
        gaze.note(NSEvent.mouseLocation, at: now)
    }

    // No `deinit` cleanup: the monitors are `Any?` and so cannot be touched
    // from a nonisolated deinit under strict concurrency. `setActive(false)`
    // is the way out, and the panel calls it whenever the buddy stops being
    // eligible — including when it hides.
}
