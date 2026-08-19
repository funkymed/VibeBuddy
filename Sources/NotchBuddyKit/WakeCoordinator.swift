import Foundation

/// The only thing in this app allowed to create a timer.
///
/// # Why this exists
///
/// The reference implementation runs seven independent wake sources — 1 Hz
/// session polling, 10 Hz mouse polling, 1 Hz Accessibility queries, 60 s usage
/// refresh, 30 min update checks, 2 s hotkey polling, plus eighteen
/// `repeatForever` animations — and calls `stop()` on none of them. They keep
/// firing while the window is hidden, while the screen is locked, and on
/// battery. No single one is unreasonable; the accumulation is, and nothing in
/// that architecture prevents an eighth from being added.
///
/// So: one timer, one owner, one place to audit. A `Timer` created anywhere else
/// in this codebase is a review failure, not a missed optimisation.
///
/// # How it keeps the budget
///
/// A single `DispatchSourceTimer` ticks at the shortest registered cadence.
/// Clients whose own cadence is longer are skipped until their interval has
/// elapsed, so registering ten `.lazy` clients still costs one wakeup every
/// 30 s — not ten.
///
/// The timer is scheduled with generous leeway (25 % of the interval), which
/// lets the kernel coalesce our wakeups with other timers already scheduled on
/// the system. Coalesced wakeups are close to free; uncoalesced ones are what
/// drains a battery.
///
/// On sleep or screen lock the timer is *cancelled*, not slowed. The budget at
/// that point is zero wakeups, not few.
@MainActor
public final class WakeCoordinator {

    /// Fraction of the tick interval handed to the kernel as scheduling slack.
    /// Higher values coalesce better; too high and a 1 s cadence visibly drifts.
    private static let leewayFraction: Double = 0.25

    private struct Entry {
        let id: String
        var cadence: Cadence
        var lastFired: TimeInterval
        let onWake: @MainActor () -> Void
    }

    private var entries: [String: Entry] = [:]
    private var timer: DispatchSourceTimer?
    private var scheduledInterval: TimeInterval?

    /// True while suspended for sleep or screen lock. No timer exists in this
    /// state — `resume()` rebuilds it.
    public private(set) var isSuspended = false

    /// Total wakeups delivered since launch. Read by `PerfProbe` and by the
    /// diagnostics panel; the number that matters for the energy budget.
    public private(set) var tickCount: Int = 0

    public init() {}

    // MARK: - Registration

    /// Register a subsystem. Re-registering the same id replaces the previous
    /// entry, so this is safe to call on reconfiguration.
    public func register(
        id: String,
        cadence: Cadence,
        onWake: @escaping @MainActor () -> Void
    ) {
        entries[id] = Entry(
            id: id,
            cadence: cadence,
            lastFired: Self.now(),
            onWake: onWake
        )
        reschedule()
    }

    public func setCadence(_ cadence: Cadence, for id: String) {
        guard var entry = entries[id], entry.cadence != cadence else { return }
        entry.cadence = cadence
        entries[id] = entry
        reschedule()
    }

    public func unregister(id: String) {
        guard entries.removeValue(forKey: id) != nil else { return }
        reschedule()
    }

    public func cadence(for id: String) -> Cadence? {
        entries[id]?.cadence
    }

    // MARK: - Suspension

    /// Called on system sleep and on screen lock. Tears the timer down entirely.
    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        reschedule()
    }

    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        // Reset the clocks so waking the machine doesn't fire every overdue
        // client at once.
        let now = Self.now()
        for key in entries.keys {
            entries[key]?.lastFired = now
        }
        reschedule()
    }

    // MARK: - Introspection

    /// The interval the shared timer currently runs at, or nil when no timer
    /// exists. This is the app's entire periodic wake cost.
    public var effectiveInterval: TimeInterval? { scheduledInterval }

    /// Steady-state wakeups per second. The budget is < 2/s at rest, 0 when
    /// suspended.
    public var wakeupsPerSecond: Double {
        guard let interval = scheduledInterval, interval > 0 else { return 0 }
        return 1 / interval
    }

    /// Shortest interval among a set of cadences, or nil if none want waking.
    ///
    /// Pure and static so the scheduling rule can be tested without a run loop.
    public nonisolated static func effectiveInterval(for cadences: [Cadence]) -> TimeInterval? {
        cadences.compactMap(\.interval).min()
    }

    // MARK: - Scheduling

    private func reschedule() {
        let target = isSuspended
            ? nil
            : Self.effectiveInterval(for: entries.values.map(\.cadence))

        guard target != scheduledInterval else { return }

        timer?.cancel()
        timer = nil
        scheduledInterval = target

        guard let interval = target else { return }

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * Self.leewayFraction * 1000))
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        source.resume()
        timer = source
    }

    private func tick() {
        tickCount += 1
        let now = Self.now()
        for (key, entry) in entries {
            guard let interval = entry.cadence.interval else { continue }
            // Tolerate the leeway we asked for, otherwise a client whose cadence
            // equals the tick interval skips every other tick.
            let due = now - entry.lastFired >= interval * (1 - Self.leewayFraction)
            guard due else { continue }
            entries[key]?.lastFired = now
            entry.onWake()
        }
    }

    /// Monotonic clock. Wall time would make a manual clock change fire every
    /// client at once, or stall them all for hours.
    private nonisolated static func now() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
