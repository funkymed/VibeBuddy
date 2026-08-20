import Foundation
import VibeBuddyKit
import ServiceManagement

/// The login item, and an honest answer when there cannot be one.
///
/// `SMAppService.mainApp` needs a bundle. This app is currently a bare binary in
/// `.build/release` — RFC-011 is what turns it into a `.app` — so registering
/// throws, and a toggle that silently fails is worse than one that says why.
///
/// The reference implementation has the other half of this lesson
/// (`BuddyPreferences.swift:453-456`): `didSet` does not fire from `init`, so a
/// stored `true` never reaches the system on launch and the setting quietly
/// lies. Reading the live status rather than the stored flag is the fix, and it
/// is why `state()` asks `SMAppService` instead of `UserDefaults`.
enum StartAtLogin {

    struct State: Equatable {
        let isEnabled: Bool
        let isAvailable: Bool
    }

    /// Whether the app is bundled at all. Unbundled means no login item.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static func state() -> State {
        guard isAvailable else { return State(isEnabled: false, isAvailable: false) }
        return State(isEnabled: SMAppService.mainApp.status == .enabled, isAvailable: true)
    }

    /// Apply, then report what the system actually did — never what was asked.
    @discardableResult
    static func set(_ enabled: Bool) -> State {
        guard isAvailable else { return State(isEnabled: false, isAvailable: false) }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            PerfProbe.log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        return state()
    }
}
