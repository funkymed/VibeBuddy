import Foundation
import VibeBuddyKit
import ServiceManagement

/// The login item, and an honest answer when there cannot be one.
enum StartAtLogin {
    struct State: Equatable {
        let isEnabled: Bool
        let isAvailable: Bool
    }

    /// Whether the app is bundled at all.
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
