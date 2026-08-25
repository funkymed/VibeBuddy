import Foundation
import Observation
import VibeHookProtocol

/// The permission requests waiting on a person, oldest first. Nothing here may fail to
/// answer. Every request that goes in holds a live socket connection open on the other
/// side, and a connection that is never answered is a Claude Code that waits out its 120
/// s timeout.
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

    /// What the user is being asked right now, or nil.
    public var head: PermissionRequestModel? { entries.first?.model }

    /// How many are behind the head.
    public var waiting: Int { max(0, entries.count - 1) }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// Everything waiting, oldest first.
    public var models: [PermissionRequestModel] { entries.map(\.model) }

    /// Rules already granted, read fresh each time rather than cached: the user edits
    /// `settings.json` by hand, and a stale copy would grant something they have just
    /// taken back.
    @ObservationIgnored public var alwaysAllowed: @MainActor () -> Set<String> = { [] }

    /// Fired whenever the head changes — a request arrived, or the one on screen was
    /// answered.
    @ObservationIgnored public var onChange: @MainActor () -> Void = {}

    public init() {}

    /// The `HookEventSink` path, in the isolation this class lives in.
    public func handle(_ request: HookRequest, from pid: pid_t?) async -> HookDecision? {
        guard request.event == .permissionRequest,
              let model = PermissionRequestModel.parse(request, from: pid)
        else { return nil }

        // Short circuit before queueing, not after: a rule the user has already granted
        // must never put a panel on screen.
        if isAlreadyAllowed(model) { return .allow }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                entries.append(Entry(model: model, reply: continuation))
                onChange()
            }
        } onCancel: {
            // The server cancels this task when the peer hangs up — the user answered
            // in the terminal.
            Task { @MainActor [weak self] in
                self?.finish(model.id, with: nil)
            }
        }
    }

    /// Whether a request matches a rule already in `permissions.allow`.
    public func isAlreadyAllowed(_ model: PermissionRequestModel) -> Bool {
        // A question is never short-circuited. Read in Claude Code 2.1.239: a tool
        // declaring `requiresUserInteraction` asks every time — an allow rule cannot
        // silence it — and any `allow` a hook returns for one is discarded.
        if case .question = model.summary { return false }
        let granted = alwaysAllowed()
        guard !granted.isEmpty else { return false }
        return granted.contains { rule in
            !rule.contains("(") && rule == model.toolName
        }
    }

    /// The user's answer.
    public func decide(_ id: String, _ decision: HookDecision) {
        finish(id, with: decision)
    }

    public func allow(_ id: String) { decide(id, .allow) }

    public func deny(_ id: String, message: String) { decide(id, .deny(message: message)) }

    /// Drops a request without an answer: Claude Code falls back to its own prompt.
    public func expire(_ id: String) { finish(id, with: nil) }

    /// Answers everything, with no opinion.
    public func drain() {
        let ids = entries.map(\.model.id)
        for id in ids { finish(id, with: nil) }
    }

    /// The single place a continuation is resumed, and the only one allowed to be.
    private func finish(_ id: String, with decision: HookDecision?) {
        guard let index = entries.firstIndex(where: { $0.model.id == id }) else { return }
        let reply = entries[index].reply
        entries.remove(at: index)
        // Resumed before the callback: the panel it wakes reads `head`, and it must not
        // see an entry whose hook has not been answered yet.
        reply?.resume(returning: decision)
        onChange()
    }

    /// Puts a request in the queue with nobody waiting on it.
    public func insertPreview(_ model: PermissionRequestModel) {
        entries.append(Entry(model: model, reply: nil))
        onChange()
    }
}

/// Bridges the queue into the transport.
public struct PermissionSink: HookEventSink {
    private let queue: PermissionQueue

    public init(queue: PermissionQueue) {
        self.queue = queue
    }

    public func handle(_ request: HookRequest, from pid: pid_t?) async -> HookDecision? {
        await queue.handle(request, from: pid)
    }
}

/// When a request stops being worth asking about.
public enum PermissionExpiry {
    /// How long after a request the transcript may still be written to before the
    /// request counts as overtaken.
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
    func expireStale(
        activity: (PermissionRequestModel) -> Date?, now: Date = Date()
    ) {
        for model in models where PermissionExpiry.isStale(
            model, lastActivity: activity(model), now: now) {
            expire(model.id)
        }
    }

    /// Drops requests whose own terminal is already in front of the user.
    func expireIfHostIsFrontmost(_ isFrontmost: (PermissionRequestModel) -> Bool) {
        for model in models where isFrontmost(model) {
            expire(model.id)
        }
    }
}
