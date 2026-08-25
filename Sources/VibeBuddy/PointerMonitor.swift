import AppKit
import VibeBuddyKit

/// Feeds `PointerGaze` with where the mouse is. Why a monitor and not a poll.
/// `HoverProbe` polls, and its own note says what that costs: `NSEvent.mouseLocation` is
/// a window-server round trip, and at 10 Hz it measured 6,3 wakeups/s against a resting
/// budget of 2.
@MainActor
final class PointerMonitor {
    /// Floor between two samples while the face is following the pointer. Mouse events
    /// arrive at the display's rate on a trackpad and faster on some mice; the face
    /// redraws at 30 Hz at best, so anything above that is work thrown away.
    private static let followingInterval: TimeInterval = 1.0 / 30

    /// Floor while the face is asleep and only a shake can reach it. Measured, and
    /// the reason this exists: arming the monitor whenever the pill is on screen — so a
    /// sleeping buddy can be woken by shaking at it — took scenario A from 14 idle
    /// wakeups over 465 s to 963 over 534 s, 1,58/s against a governing budget of 2.
    private static let sleepingInterval: TimeInterval = 1.0 / 12

    /// Whether the face is only listening for a shake.
    var isDormant = false

    private var minimumInterval: TimeInterval {
        isDormant ? Self.sleepingInterval : Self.followingInterval
    }

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
        // The global monitor does not see events delivered to our own app, and the
        // panel is exactly what the pointer is over when it comes to say hello.
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
        guard now.timeIntervalSince(lastSample) >= minimumInterval else { return }
        lastSample = now
        // `NSEvent.mouseLocation` rather than the event's own location: a global
        // monitor's event carries window coordinates of a window that is not ours.
        gaze.note(NSEvent.mouseLocation, at: now)
    }

    // No `deinit` cleanup: the monitors are `Any?` and so cannot be touched from a
    // nonisolated deinit under strict concurrency.
}
