import Foundation
import VibeBuddyKit
import ServiceManagement

/// The login item, and an honest answer when there cannot be one.
///
/// `SMAppService.mainApp` needs a bundle: registering throws on the bare binary
/// in `.build/release`. Do not report the state from a stored flag: `didSet`
/// never fires from `init`, so a stored `true` never reaches the system and the
/// toggle lies. Always read the live `SMAppService` status.
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
