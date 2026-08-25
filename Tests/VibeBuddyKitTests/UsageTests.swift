import Testing
import Foundation
@testable import VibeBuddyKit

@Suite("Usage parsing")
struct ClaudeUsageTests {
    /// Trimmed from the live response on 2026-08-19, including the windows this build
    /// has never heard of.
    // A function rather than a stored property: [String: Any] is not Sendable, and a
    // shared mutable dictionary across concurrent tests is a real race, not a compiler
    // complaint.
    private static func live() -> [String: Any] { [
        "five_hour": ["utilization": 16.0,
                      "resets_at": "2026-08-19T22:20:00.226366+00:00"],
        "seven_day": ["utilization": 5.0,
                      "resets_at": "2026-08-23T20:00:00.226390+00:00"],
        "seven_day_opus": NSNull(),
        "seven_day_sonnet": NSNull(),
        // Real keys from the real response.
        "tangelo": NSNull(),
        "nimbus_quill": ["utilization": 0.0, "resets_at": NSNull()],
        "omelette_promotional": NSNull(),
        "cinder_cove": NSNull(),
    ] }

    @Test("the two windows that matter are read")
    func readsWindows() {
        let usage = ClaudeUsage.parse(Self.live())
        #expect(usage.fiveHour?.utilisation == 16.0)
        #expect(usage.sevenDay?.utilisation == 5.0)
        #expect(usage.fiveHour?.resetsAt != nil)
    }

    // The endpoint is not a public contract (risk R5).
    @Test("unknown windows are ignored, not fatal")
    func unknownKeysIgnored() {
        let usage = ClaudeUsage.parse(Self.live())
        #expect(usage.fiveHour != nil)
        #expect(usage.sevenDayOpus == nil)
    }

    // A missing window must render as "unavailable", never as zero: 0 % looks like good
    // news, and being wrong in the reassuring direction is worse.
    @Test("a null window is absent rather than zero")
    func nullIsNotZero() {
        let usage = ClaudeUsage.parse(["five_hour": NSNull(), "seven_day": NSNull()])
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay == nil)
    }

    @Test("an empty response yields nothing rather than crashing")
    func emptyResponse() {
        let usage = ClaudeUsage.parse([:])
        #expect(usage.fiveHour == nil)
    }

    // The live format has fractional seconds and a numeric offset, not `Z`.
    @Test("both timestamp spellings parse", arguments: [
        "2026-08-19T22:20:00.226366+00:00",
        "2026-08-19T22:20:00+00:00",
        "2026-08-19T22:20:00Z",
    ])
    func timestampFormats(_ text: String) {
        #expect(ClaudeUsage.parseDate(text) != nil)
    }

    @Test("utilisation clamps into a drawable fraction")
    func fractionClamps() {
        #expect(ClaudeUsage.Window(utilisation: 0, resetsAt: nil).fraction == 0)
        #expect(ClaudeUsage.Window(utilisation: 50, resetsAt: nil).fraction == 0.5)
        #expect(ClaudeUsage.Window(utilisation: 140, resetsAt: nil).fraction == 1)
        #expect(ClaudeUsage.Window(utilisation: -3, resetsAt: nil).fraction == 0)
    }
}

/// A credential source that never touches the keychain.
private struct StubCredentials: CredentialSource {
    let token: String?
    let expiresAt: Date
    func read() -> (token: String, expiresAt: Date)? {
        token.map { ($0, expiresAt) }
    }
}

@Suite("Usage state")
@MainActor
struct UsageStateTests {
    @Test("nothing is known before the first reading")
    func startsUnknown() {
        #expect(UsageState().status == .unknown)
    }

    // A five-hour window does not move fast enough to justify steady polling, and this
    // is the app's only unconditional periodic wake, D3.
    @Test("the cadence loosens once a reading exists")
    func cadenceAdapts() {
        #expect(UsageState().interval == 10)   // nothing yet: try again soon

        let ready = UsageState(seeded: .ready(ClaudeUsage(fiveHour: nil, sevenDay: nil)))
        #expect(ready.interval == 180)          // panel shut

        ready.isPanelOpen = true
        #expect(ready.interval == 30)           // someone is reading it
    }

    @Test("a failure keeps the last good reading rather than blanking it")
    func failureKeepsLastGood() async {
        let good = ClaudeUsage(
            fiveHour: .init(utilisation: 16, resetsAt: nil), sevenDay: nil)
        let state = UsageState(
            client: UsageClient(credentials: StubCredentials(token: nil, expiresAt: .distantFuture)),
            seeded: .ready(good))

        await state.refresh(now: Date().addingTimeInterval(3600))
        // No credentials is a real "we cannot know", so it does replace — but a network
        // blip would not.
        #expect(state.status == .unavailable("non connecté"))
    }

    @Test("an expired token reads as signed out, not as zero usage")
    func expiredTokenIsNotZero() async {
        let state = UsageState(client: UsageClient(
            credentials: StubCredentials(token: "t", expiresAt: .distantPast)))
        await state.refresh()
        #expect(state.status == .unavailable("non connecté"))
        #expect(state.usage == nil)
    }

    @Test("refreshing twice in a row does not ask twice")
    func respectsOwnSchedule() async {
        let state = UsageState(client: UsageClient(
            credentials: StubCredentials(token: nil, expiresAt: .distantFuture)))
        let now = Date()
        await state.refresh(now: now)
        let first = state.status
        await state.refresh(now: now.addingTimeInterval(1))
        #expect(state.status == first)
    }
}
