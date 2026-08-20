import Testing
import Foundation
@testable import VibeBuddyKit

// The scheduling rule is the whole point of WakeCoordinator, so it is tested as
// pure arithmetic rather than by waiting on real timers.

@Suite("Cadence")
struct CadenceTests {

    @Test("off never wakes")
    func offHasNoInterval() {
        #expect(Cadence.off.interval == nil)
    }

    @Test("intervals are ordered coarse to fine")
    func intervalsOrdered() {
        #expect(Cadence.lazy.interval! > Cadence.idle.interval!)
        #expect(Cadence.idle.interval! > Cadence.active.interval!)
    }

    @Test("every case is covered")
    func allCases() {
        #expect(Cadence.allCases.count == 4)
    }

}

@Suite("WakeCoordinator scheduling")
struct WakeSchedulingTests {

    @Test("no clients means no timer")
    func emptyIsSilent() {
        #expect(WakeCoordinator.effectiveInterval(for: []) == nil)
    }

    @Test("only off clients means no timer")
    func allOffIsSilent() {
        #expect(WakeCoordinator.effectiveInterval(for: [.off, .off]) == nil)
    }

    @Test("the shortest cadence sets the tick")
    func shortestWins() {
        #expect(WakeCoordinator.effectiveInterval(for: [.lazy, .active, .idle]) == 1)
        #expect(WakeCoordinator.effectiveInterval(for: [.lazy, .idle]) == 5)
        #expect(WakeCoordinator.effectiveInterval(for: [.lazy, .off]) == 30)
    }

    // The budget in RFC-001 is < 2 wakeups/s at rest. Ten lazy clients must
    // still cost one wakeup every 30 s, not ten — that is the entire reason the
    // coordinator exists rather than each subsystem owning a timer.
    @Test("many lazy clients still cost one timer")
    func lazyClientsShareOneTimer() {
        let many = Array(repeating: Cadence.lazy, count: 10)
        #expect(WakeCoordinator.effectiveInterval(for: many) == 30)
    }

    // Every cadence is now a resting cadence: hover went event-driven, so
    // nothing wants a rate finer than 1 Hz any more.
    @Test("the worst resting cadence stays inside the budget")
    func worstRestingCaseWithinBudget() {
        let interval = WakeCoordinator.effectiveInterval(for: Cadence.resting)!
        #expect(1 / interval <= 2)
    }

}

@Suite("WakeCoordinator lifecycle")
@MainActor
struct WakeLifecycleTests {

    @Test("registering a client starts the timer")
    func registerStartsTimer() {
        let wake = WakeCoordinator()
        #expect(wake.effectiveInterval == nil)
        wake.register(id: "a", cadence: .idle) {}
        #expect(wake.effectiveInterval == 5)
    }

    @Test("suspend tears the timer down to nothing")
    func suspendIsZeroNotSlow() {
        let wake = WakeCoordinator()
        wake.register(id: "a", cadence: .active) {}
        #expect(wake.wakeupsPerSecond == 1)

        wake.suspend()
        #expect(wake.effectiveInterval == nil)
        #expect(wake.wakeupsPerSecond == 0)

        wake.resume()
        #expect(wake.effectiveInterval == 1)
    }

    @Test("changing cadence reschedules")
    func cadenceChangeReschedules() {
        let wake = WakeCoordinator()
        wake.register(id: "a", cadence: .lazy) {}
        #expect(wake.effectiveInterval == 30)
        wake.setCadence(.active, for: "a")
        #expect(wake.effectiveInterval == 1)
        wake.setCadence(.off, for: "a")
        #expect(wake.effectiveInterval == nil)
    }

    @Test("unregistering the last client stops the timer")
    func unregisterStops() {
        let wake = WakeCoordinator()
        wake.register(id: "a", cadence: .idle) {}
        wake.unregister(id: "a")
        #expect(wake.effectiveInterval == nil)
    }

    @Test("re-registering replaces rather than duplicates")
    func reRegisterReplaces() {
        let wake = WakeCoordinator()
        wake.register(id: "a", cadence: .lazy) {}
        wake.register(id: "a", cadence: .active) {}
        #expect(wake.cadence(for: "a") == .active)
        #expect(wake.effectiveInterval == 1)
    }

    @Test("a client actually fires", .timeLimit(.minutes(1)))
    func clientFires() async throws {
        let wake = WakeCoordinator()
        let box = Counter()
        wake.register(id: "a", cadence: .active) { box.bump() }
        try await Task.sleep(for: .milliseconds(2_500))
        #expect(box.value >= 1)
    }
}

@MainActor
private final class Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
