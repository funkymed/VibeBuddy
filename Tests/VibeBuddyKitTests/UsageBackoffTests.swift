import Foundation
import Testing
@testable import VibeBuddyKit

/// What the app does while the endpoint refuses.
@Suite("Usage backoff")
@MainActor
struct UsageBackoffTests {
    /// A client that answers whatever the test wants, without a network.
    private struct Stub: CredentialSource {
        func read() -> (token: String, expiresAt: Date)? { ("t", .distantFuture) }
    }

    private func state(seeded: UsageState.Status = .unknown) -> UsageState {
        // No cache: these tests are about the schedule, and a stored reading from a
        // previous run would make "unknown" mean something else.
        UsageState(seeded: seeded, cache: nil)
    }

    @Test("a fresh state asks immediately")
    func firstAttemptIsNow() {
        #expect(state().interval == 10)
    }

    @Test("a reading slows the polling right down")
    func readyIsLazy() {
        let usage = ClaudeUsage(fiveHour: nil, sevenDay: nil)
        let ready = state(seeded: .ready(usage))
        #expect(ready.interval == 180)
        ready.isPanelOpen = true
        #expect(ready.interval == 30)
    }

    @Test("the backoff doubles and then stops")
    func backoffDoublesToCeiling() {
        let usage = state()
        var seen: [TimeInterval] = []
        for count in 1...12 {
            usage.setLimitsForTesting(count)
            seen.append(usage.backoff)
        }
        #expect(seen.first == UsageState.backoffFloor)
        #expect(seen[1] == 120)
        #expect(seen[2] == 240)
        #expect(seen.last == UsageState.backoffCeiling)
        // Never goes backwards: a schedule that shortens under refusal is the bug this
        // replaces.
        #expect(seen == seen.sorted())
    }

    @Test("a reading that arrives clears the backoff")
    func successResets() {
        let usage = state()
        usage.setLimitsForTesting(4)
        #expect(usage.interval > 60)
        usage.clearLimitsForTesting()
        #expect(usage.interval == 10)
    }

    @Test("an age is only reported when there is a reading")
    func ageNeedsAReading() {
        #expect(state().age() == nil)
        let fetched = Date(timeIntervalSinceNow: -300)
        let ready = state(seeded: .ready(
            ClaudeUsage(fiveHour: nil, sevenDay: nil, fetchedAt: fetched)))
        #expect((ready.age() ?? 0) >= 299)
    }
}

/// The cache, which is what stops a rate-limited launch from showing nothing.
@Suite("Usage cache")
struct UsageCacheTests {
    /// Created, used, wiped: an untouched suite still leaves a plist behind.
    private func withCache(_ body: (UsageCache) throws -> Void) rethrows {
        let name = "vibebuddy.usage.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(UsageCache(defaults: defaults))
    }

    @Test("a reading survives a round trip")
    func roundTrip() throws {
        try withCache { store in
            let usage = ClaudeUsage(
                fiveHour: .init(utilisation: 6, resetsAt: Date()),
                sevenDay: .init(utilisation: 12, resetsAt: nil))
            store.save(usage)
            let loaded = try #require(store.load())
            #expect(loaded.fiveHour?.utilisation == 6)
            #expect(loaded.sevenDay?.utilisation == 12)
        }
    }

    // A five-hour window resets.
    @Test("a reading older than the window is dropped, not shown")
    func expires() {
        withCache { store in
            store.save(ClaudeUsage(
                fiveHour: .init(utilisation: 50, resetsAt: nil), sevenDay: nil,
                fetchedAt: Date(timeIntervalSinceNow: -6 * 3600)))
            #expect(store.load() == nil)
        }
    }

    @Test("nothing stored means nothing loaded")
    func empty() {
        withCache { store in
            #expect(store.load() == nil)
        }
    }
}
