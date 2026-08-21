import Foundation
import Observation
import VibeHookProtocol

/// The permission requests waiting on a person, oldest first.
///
/// **A queue, not a single slot.** The reference implementation held one
/// "pending" request, and its own comment records the regression: a burst of
/// parallel tool calls made every new request silently deny the one before it,
/// and only the last survived. Claude Code runs tools in parallel routinely, so
/// this is the normal case, not the edge one. RFC-007, T2.
///
/// **Nothing here may fail to answer.** Every request that goes in holds a live
/// socket connection open on the other side, and a connection that is never
/// answered is a Claude Code that waits out its 120 s timeout. Every path —
/// decided, expired, cancelled, app quitting — resumes exactly once.
@MainActor
@Observable
public final class PermissionQueue {

    /// One request, and the promise made to the hook that asked it.
    private struct Entry {
        let model: PermissionRequestModel
        /// Resumed exactly once, by `finish(_:with:)` and nowhere else.
        var reply: CheckedContinuation<HookDecision?, Never>?
    }

    private var entries: [Entry] = []

    /// What the user is being asked right now, or nil. The panel draws this one
    /// and counts the rest — see `waiting`.
    public var head: PermissionRequestModel? { entries.first?.model }

    /// How many are behind the head. Past three or four, a queue says something
    /// is wrong rather than something is pending, so the panel shows a number
    /// instead of a list. Arbitrage of 2026-08-21, answers Q2.
    public var waiting: Int { max(0, entries.count - 1) }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// Everything waiting, oldest first. Copied out on purpose: the expiries
    /// below remove entries while they walk them.
    public var models: [PermissionRequestModel] { entries.map(\.model) }

    /// Rules already granted, read fresh each time rather than cached: the user
    /// edits `settings.json` by hand, and a stale copy would grant something
    /// they have just taken back.
    ///
    /// Injected so the tests never touch the disk, and so RFC-007 T7 can hand
    /// it the `ClaudeSettingsWriter` without this type learning the file's
    /// shape.
    @ObservationIgnored public var alwaysAllowed: @MainActor () -> Set<String> = { [] }

    /// Fired whenever the head changes — a request arrived, or the one on
    /// screen was answered. An explicit callback rather than observation
    /// tracking, like `SessionCoordinator`: the panel is an `NSPanel` whose
    /// content is rebuilt by hand, not a view that re-evaluates itself.
    @ObservationIgnored public var onChange: @MainActor () -> Void = {}

    public init() {}

    // MARK: - Coming in

    /// The `HookEventSink` path, in the isolation this class lives in.
    ///
    /// Returns `nil` for anything that is not a permission request: `nil` is
    /// the protocol's "no opinion", and an event nobody has claimed must leave
    /// Claude Code exactly as it found it.
    public func handle(_ request: HookRequest, from pid: pid_t?) async -> HookDecision? {
        guard request.event == .permissionRequest,
              let model = PermissionRequestModel.parse(request, from: pid)
        else { return nil }

        // Short circuit before queueing, not after: a rule the user has already
        // granted must never put a panel on screen.
        if isAlreadyAllowed(model) { return .allow }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                entries.append(Entry(model: model, reply: continuation))
                onChange()
            }
        } onCancel: {
            // The server cancels this task when the peer hangs up — the user
            // answered in the terminal. Someone has to resume the continuation,
            // and it is this.
            Task { @MainActor [weak self] in
                self?.finish(model.id, with: nil)
            }
        }
    }

    /// Whether a request matches a rule already in `permissions.allow`.
    ///
    /// Only **bare** entries are compared, against the tool's name. Claude Code
    /// owns its own pattern language — `Bash(npm install:*)` — and its matcher
    /// has already run by the time a request reaches us: a scoped rule that
    /// matched would never have asked. Reimplementing that language here is how
    /// the two drift apart, so a scoped entry is deliberately ignored.
    public func isAlreadyAllowed(_ model: PermissionRequestModel) -> Bool {
        let granted = alwaysAllowed()
        guard !granted.isEmpty else { return false }
        return granted.contains { rule in
            !rule.contains("(") && rule == model.toolName
        }
    }

    // MARK: - Going out

    /// The user's answer. Unknown ids are ignored rather than trapped: a panel
    /// can outlive the request it was drawn for.
    public func decide(_ id: String, _ decision: HookDecision) {
        finish(id, with: decision)
    }

    public func allow(_ id: String) { decide(id, .allow) }

    public func deny(_ id: String, message: String) { decide(id, .deny(message: message)) }

    /// Drops a request without an answer: Claude Code falls back to its own
    /// prompt. Used by the three expiries of T3.
    public func expire(_ id: String) { finish(id, with: nil) }

    /// Answers everything, with no opinion. Called when the app is going away:
    /// a queue that dies holding continuations is a Claude Code that waits out
    /// its timeout for every one of them.
    public func drain() {
        let ids = entries.map(\.model.id)
        for id in ids { finish(id, with: nil) }
    }

    /// The single place a continuation is resumed, and the only one allowed to
    /// be. Removing the entry first makes a second call a no-op rather than a
    /// crash — `resume` twice traps.
    private func finish(_ id: String, with decision: HookDecision?) {
        guard let index = entries.firstIndex(where: { $0.model.id == id }) else { return }
        let reply = entries[index].reply
        entries.remove(at: index)
        // Resumed before the callback: the panel it wakes reads `head`, and it
        // must not see an entry whose hook has not been answered yet.
        reply?.resume(returning: decision)
        onChange()
    }

    /// Puts a request in the queue with **nobody waiting on it**.
    ///
    /// For `--simulate-permission`, which exists because the alternative is
    /// judging a panel's rendering by running Claude Code and hoping it asks
    /// for the right kind of thing. A preview entry carries no continuation,
    /// so answering it decides nothing — which is exactly what a rehearsal is.
    public func insertPreview(_ model: PermissionRequestModel) {
        entries.append(Entry(model: model, reply: nil))
        onChange()
    }
}

/// Bridges the queue into the transport.
///
/// A separate value rather than a conformance on the queue itself: the sink is
/// `Sendable` and called from the server's own context, while the queue lives
/// on the main actor with the views that read it. This is where the hop
/// happens, and it is the only place it does.
public struct PermissionSink: HookEventSink {
    private let queue: PermissionQueue

    public init(queue: PermissionQueue) {
        self.queue = queue
    }

    public func handle(_ request: HookRequest, from pid: pid_t?) async -> HookDecision? {
        await queue.handle(request, from: pid)
    }
}

// MARK: - The three expiries

/// When a request stops being worth asking about. RFC-007, T3.
///
/// All three are **event-driven**, and that is a requirement rather than a
/// preference: the exit criterion says zero wakeups while a request is waiting,
/// which rules out polling for any of them.
///
/// | Expiry | What drives it |
/// |---|---|
/// | The user answered in the terminal | the peer hangs up; the server races it against the sink and cancels — handled in `handle(_:from:)` |
/// | Claude moved on | the transcript is written to; `ProjectsWatcher` already sees it (RFC-003) |
/// | The terminal is already in front | `NSWorkspace` says an app came forward |
public enum PermissionExpiry {

    /// How long after a request the transcript may still be written to before
    /// the request counts as overtaken.
    ///
    /// **Sixty seconds, and the number is the whole lesson.** It was two, taken
    /// from the reference, on the reasoning that the tool call is written
    /// *before* the permission is asked so any later entry belongs to what
    /// happened next. Measured against a real Claude Code on 2026-08-21: the
    /// transcript is still being written when the prompt goes up, so the
    /// request expired **its own panel**, about two seconds after it appeared.
    /// From the outside it looked exactly like a panel that opens and closes.
    ///
    /// This expiry is a safety net, not the mechanism: the user answering in
    /// the terminal is detected by the peer hanging up, which is immediate and
    /// certain. What is left for this to catch is an app that missed a hang-up,
    /// and for that a minute is soon enough. A net that fires before the thing
    /// it protects has happened is not a net.
    public static let staleAfter: TimeInterval = 60

    /// Whether a request has been overtaken by its own session.
    public static func isStale(
        _ model: PermissionRequestModel, lastActivity: Date?, now: Date = Date()
    ) -> Bool {
        guard let lastActivity else { return false }
        return lastActivity > model.receivedAt.addingTimeInterval(staleAfter)
    }
}

public extension PermissionQueue {

    /// Drops requests whose session has moved on without them.
    ///
    /// `activity` is asked per request rather than handed a table: matching is
    /// by `sessionID`, and the caller is the only thing that knows how to fall
    /// back to `cwd` when the two do not agree.
    func expireStale(
        activity: (PermissionRequestModel) -> Date?, now: Date = Date()
    ) {
        for model in models where PermissionExpiry.isStale(
            model, lastActivity: activity(model), now: now) {
            expire(model.id)
        }
    }

    /// Drops requests whose own terminal is already in front of the user.
    ///
    /// They are about to answer there, and a panel over the window they are
    /// looking at is a second prompt for one question.
    func expireIfHostIsFrontmost(_ isFrontmost: (PermissionRequestModel) -> Bool) {
        for model in models where isFrontmost(model) {
            expire(model.id)
        }
    }
}
