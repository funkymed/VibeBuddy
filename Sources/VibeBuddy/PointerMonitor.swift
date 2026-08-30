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

    // One rate for every face, the sleeping one included — decided 2026-08-30. A 12 Hz
    // dormant floor lived here (a face that follows nothing needs fewer samples, and it
    // brought a 1,58 wakeups/s regression back to 0,261), but a vigorous shake runs at
    // 5-8 Hz, which 12 Hz cannot see: the one gesture that must reach a sleeping face
    // is the one that rate hides. The cost only lands while the pointer is moving; at
    // rest the monitor emits nothing. Scenario A is to be re-measured before release.

    /// Set from the environment, so a shake that is not being caught can be watched
    /// instead of guessed at: `VIBEBUDDY_GAZE_TRACE=1`. Reasoning cost this repository
    /// four days on the socket suite; a trace settled it in one run.
    static let traces = ProcessInfo.processInfo.environment["VIBEBUDDY_GAZE_TRACE"] == "1"

    /// Told after every sample that got through the throttle, so the panel can react to
    /// what the gaze made of it without polling.
    var onSample: (() -> Void)?

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
        guard now.timeIntervalSince(lastSample) >= Self.followingInterval else { return }
        lastSample = now
        // `NSEvent.mouseLocation` rather than the event's own location: a global
        // monitor's event carries window coordinates of a window that is not ours.
        let wasChasing = gaze.isChasing
        gaze.note(NSEvent.mouseLocation, at: now)
        if Self.traces {
            FileHandle.standardError.write(Data(String(
                format: "gaze: %@ chase=%@%@\n",
                NSStringFromPoint(NSEvent.mouseLocation),
                gaze.isChasing ? "OUI" : "non",
                (!wasChasing && gaze.isChasing) ? "  ← CHASSE DÉCLENCHÉE" : "").utf8))
        }
        onSample?()
    }

    // No `deinit` cleanup: the monitors are `Any?` and so cannot be touched from a
    // nonisolated deinit under strict concurrency.
}
