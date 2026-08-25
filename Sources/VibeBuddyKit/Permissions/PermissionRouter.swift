import Foundation
import VibeHookProtocol

/// What the panel shows a person, and what answering it does.
///
/// Extracted from `NotchPanel` so the routing — which request is on screen,
/// which consent is pending, and in what order the two get answered and
/// written — can be exercised without a window. It holds no AppKit and draws
/// nothing: it decides, the panel performs.
///
/// The split is deliberate at the call site too. `set(_:waiting:)` returns a
/// verdict rather than acting, because the panel has to remeasure its height
/// *before* it moves its state — see the note in `NotchPanel.setPermission`.
///
/// Every request here holds a socket open on the other side: each path —
/// decided, expired, cancelled, app quitting — answers exactly once, or Claude
/// Code waits its full 120 s.
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

    /// The permission on screen. Held as a plain value like the rest of the
    /// panel's inputs: observing the queue would re-evaluate the view on every
    /// change to it.
    public private(set) var permission: PermissionRequestModel?
    public private(set) var waiting = 0
    public private(set) var consent: PermissionConsent?

    public var onDecision: ((String, HookDecision?) -> Void)?
    /// Asked to build the consent for a request, and to write it once confirmed.
    /// Held as closures so the panel never learns the shape of the settings file.
    public var onAlwaysAllowAsked: ((PermissionRequestModel) -> PermissionConsent?)?
    public var onConsentConfirmed: ((PermissionConsent) -> Void)?

    public init() {}

    /// Whether the panel is holding something that waits on a **person**.
    ///
    /// A panel opened by hovering closes when the pointer leaves — that is what
    /// hovering means. A panel that opened by itself to ask a question did not
    /// come from the pointer, and it does not go with it: the user reads the
    /// question, looks away, goes back to their terminal to check something,
    /// and comes back. Closing under them mid-thought is the same mistake as
    /// the « terminal au premier plan » expiry of 2026-08-21 — an alert may be
    /// withdrawn, a question may not. It leaves when it is answered, and by no
    /// other route.
    ///
    /// The pointer can still open the panel; only the closing is held.
    public var isHoldingAnAsk: Bool { permission != nil || consent != nil }

    /// Takes a request, or takes the last one away, and says what changed.
    ///
    /// The guard compares **identifiers, not models**: two models sharing an id
    /// are the same request, and replaying the whole sequence for them costs a
    /// remeasure and an animation for nothing.
    public func set(_ model: PermissionRequestModel?, waiting: Int) -> Verdict {
        let had = permission != nil
        guard model?.id != permission?.id || waiting != self.waiting else {
            return Verdict(changed: false, hasRequest: had, wasShowingSomething: false)
        }
        permission = model
        self.waiting = waiting

        // The request went away under the consent screen — expired, or
        // answered in the terminal. There is nothing left to grant.
        let hadConsent = consent != nil
        if model == nil, hadConsent { consent = nil }

        return Verdict(changed: true, hasRequest: model != nil,
                       wasShowingSomething: hadConsent || had)
    }

    /// Answers the request on screen, if there still is one. Silent otherwise:
    /// a router that remembered the last id would answer it twice.
    public func answer(_ decision: HookDecision?) {
        guard let id = permission?.id else { return }
        onDecision?(id, decision)
    }

    /// « Toujours autoriser » is a decision **and** a write to the user's own
    /// settings. The two are separated on purpose: this builds the exact diff
    /// and waits (T8). Nothing is written until it comes back confirmed.
    ///
    /// When there is nothing to write — the rule is already granted — it is
    /// simply an allow, with no screen in the way.
    ///
    /// - Returns: true when a consent screen must now be drawn; false when it
    ///   has already answered `.allow` and there is nothing to show.
    public func alwaysAllow() -> Bool {
        guard let model = permission, let pending = onAlwaysAllowAsked?(model)
        else { answer(.allow); return false }
        consent = pending
        return true
    }

    public func cancelConsent() { consent = nil }

    /// Writes, then answers. In that order: an allow that reached Claude Code
    /// before the rule was on disk would be granted once and asked again next
    /// time, which reads as the button not working.
    public func confirmConsent() {
        guard let pending = consent else { return }
        consent = nil
        onConsentConfirmed?(pending)
        answer(.allow)
    }
}
