import Foundation
import VibeHookProtocol

/// What the panel shows a person, and what answering it does. Every request here holds a
/// socket open on the other side: each path — decided, expired, cancelled, app quitting
/// — answers exactly once, or Claude Code waits its full 120 s.
@MainActor
public final class PermissionRouter {
    /// What `set(_:waiting:)` decided; the panel performs it.
    public struct Verdict: Sendable, Equatable {
        /// False means the guard tripped: do nothing at all, not even remeasure.
        public let changed: Bool
        /// Whether there is a request on screen now.
        public let hasRequest: Bool
        /// Was already showing a request or a consent: swap, do not reopen.
        public let wasShowingSomething: Bool

        public init(changed: Bool, hasRequest: Bool, wasShowingSomething: Bool) {
            self.changed = changed
            self.hasRequest = hasRequest
            self.wasShowingSomething = wasShowingSomething
        }
    }

    public private(set) var permission: PermissionRequestModel?
    public private(set) var waiting = 0
    public private(set) var consent: PermissionConsent?

    public var onDecision: ((String, HookDecision?) -> Void)?
    /// Asked to build the consent for a request, and to write it once confirmed.
    public var onAlwaysAllowAsked: ((PermissionRequestModel) -> PermissionConsent?)?
    public var onConsentConfirmed: ((PermissionConsent) -> Void)?

    public init() {}

    /// Whether the panel is holding something that waits on a person.
    public var isHoldingAnAsk: Bool { permission != nil || consent != nil }

    /// Takes a request, or takes the last one away, and says what changed.
    public func set(_ model: PermissionRequestModel?, waiting: Int) -> Verdict {
        let had = permission != nil
        guard model?.id != permission?.id || waiting != self.waiting else {
            return Verdict(changed: false, hasRequest: had, wasShowingSomething: false)
        }
        permission = model
        self.waiting = waiting

        // The request went away under the consent screen — expired, or answered in the
        // terminal.
        let hadConsent = consent != nil
        if model == nil, hadConsent { consent = nil }

        return Verdict(changed: true, hasRequest: model != nil,
                       wasShowingSomething: hadConsent || had)
    }

    /// Answers the request on screen, if there still is one.
    public func answer(_ decision: HookDecision?) {
        guard let id = permission?.id else { return }
        onDecision?(id, decision)
    }

    /// « Toujours autoriser » is a decision and a write to the user's own settings.
    public func alwaysAllow() -> Bool {
        guard let model = permission, let pending = onAlwaysAllowAsked?(model)
        else { answer(.allow); return false }
        consent = pending
        return true
    }

    public func cancelConsent() { consent = nil }

    /// Writes, then answers.
    public func confirmConsent() {
        guard let pending = consent else { return }
        consent = nil
        onConsentConfirmed?(pending)
        answer(.allow)
    }
}
