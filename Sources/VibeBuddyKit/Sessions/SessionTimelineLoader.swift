import Foundation

/// Reads a session's recent events off the main thread, once per change.
///
/// An earlier shape of this called the parse from a view's `body`, so every invalidation
/// re-read the transcript on the main thread.
public actor SessionTimelineLoader {
    /// Four times the window `JSONLTailReader` uses: that one answers « what is this
    /// session doing now », this one has to show a history.
    public static let windowBytes = 256 * 1024

    private struct Cached {
        let modified: Date
        let size: UInt64
        let events: [TimelineEvent]
    }

    private var cache: [String: Cached] = [:]

    public init() {}

    /// Nil when the transcript is unreadable, which is not the same as a session with no
    /// events: the caller shows different things for the two.
    public func events(at path: String) -> [TimelineEvent]? {
        guard let meta = Self.stat(path) else { return nil }
        if let hit = cache[path], hit.modified == meta.modified, hit.size == meta.size {
            return hit.events
        }
        guard let data = JSONLTailReader.tail(of: path, bytes: Self.windowBytes) else {
            return nil
        }
        let events = TimelineParser.parse(data)
        cache[path] = Cached(modified: meta.modified, size: meta.size, events: events)
        return events
    }

    /// The panel shows one session at a time, so the cache holds one entry in practice.
    /// Kept as a set anyway: a queue of permissions can move the selection twice before
    /// either read lands.
    public func evict(keeping keep: Set<String>) {
        guard cache.count > keep.count else { return }
        cache = cache.filter { keep.contains($0.key) }
    }

    public var cachedCount: Int { cache.count }

    private static func stat(_ path: String) -> (modified: Date, size: UInt64)? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate
        else { return nil }
        return (modified, UInt64(values.fileSize ?? 0))
    }
}
