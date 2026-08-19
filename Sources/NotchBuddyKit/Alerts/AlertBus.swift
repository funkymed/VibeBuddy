import Foundation

/// Where alerts go.
///
/// A bus rather than a direct call into the UI, for one reason stated up front
/// in RFC-012: a phone relay is planned. With a bus that is a second subscriber;
/// with direct calls it is an edit to every site that raises an alert.
///
/// The cost of being right about this today is about forty lines.
@MainActor
public final class AlertBus {

    private var subscribers: [UUID: AsyncStream<SessionAlert>.Continuation] = [:]
    private(set) public var delivered: [SessionAlert] = []

    /// Retained history, for a diagnostics panel and for a viewer that opens
    /// after the fact. Bounded — this is not a log.
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

    public var subscriberCount: Int { subscribers.count }
}
