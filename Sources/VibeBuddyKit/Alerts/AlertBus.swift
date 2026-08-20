import Foundation

/// Where alerts go.
///
/// A bus, not a direct call into the UI: RFC-012 plans a phone relay, which is
/// a second subscriber here and an edit to every raise site otherwise.
@MainActor
public final class AlertBus {

    private var subscribers: [UUID: AsyncStream<SessionAlert>.Continuation] = [:]
    private(set) public var delivered: [SessionAlert] = []

    /// Retained history, for diagnostics and late viewers. Bounded, not a log.
    public static let historyLimit = 50

    public init() {}

    public func publish(_ alert: SessionAlert) {
        delivered.append(alert)
        if delivered.count > Self.historyLimit { delivered.removeFirst() }
        for continuation in subscribers.values { continuation.yield(alert) }
    }

    public func stream() -> AsyncStream<SessionAlert> {
        let id = UUID()
        return AsyncStream { continuation in
            subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.subscribers[id] = nil }
            }
        }
    }
}
