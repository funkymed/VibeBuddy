import Foundation

/// Reads the last few kilobytes of a transcript, and remembers what it read.
///
/// # Why a tail and not a read
///
/// Transcripts grow without bound — 8 MB for a day's work is ordinary, and the
/// corpus on this machine is 517 files. Everything the UI needs is in the last
/// handful of entries, so the file is opened, seeked to the end, and a bounded
/// window is read back.
///
/// Two of the reference implementation's three readers do not do this: they call
/// `String(contentsOf:)` on whole files, every sixty seconds, materialising the
/// file *and* a full array of substrings. That is risk R2, and it is what puts
/// its memory budget out by an order of magnitude.
///
/// # Why this is a value, not an actor
///
/// It was an actor. That forced `SessionStore` — itself an actor — to either
/// await it mid-refresh, producing a snapshot assembled from several instants,
/// or keep a second cache of its own. It kept a second cache, and then there
/// were two caches for one job.
///
/// A struct owned by `SessionStore` inherits that actor's isolation for free,
/// and a refresh reads one coherent moment.
public struct JSONLTailReader: Sendable {

    /// Enough for the last few entries. Assistant entries carrying large tool
    /// inputs run to tens of kilobytes on their own.
    public static let windowBytes = 64 * 1024

    private struct Cached {
        let modified: Date
        let size: UInt64
        let parsed: ParsedTail
    }

    private var cache: [String: Cached] = [:]

    public init() {}

    /// Parsed tail for `path`, reusing the cache when the file has not moved.
    ///
    /// Keyed on modification time *and* size: a transcript rewritten in place —
    /// which happens on compaction — can keep its size while its content
    /// changes, and can change size within the same second.
    public mutating func read(path: String, modified: Date, size: UInt64) -> ParsedTail? {
        if let hit = cache[path], hit.modified == modified, hit.size == size {
            return hit.parsed
        }
        guard let data = Self.tail(of: path, bytes: Self.windowBytes) else { return nil }
        let parsed = TranscriptParser.parse(data)
        cache[path] = Cached(modified: modified, size: size, parsed: parsed)
        return parsed
    }

    /// Forget everything not in `keep`.
    ///
    /// Claude Code never deletes a transcript, so without eviction this grows
    /// for the lifetime of the process — one entry per project ever opened.
    public mutating func evict(keeping keep: Set<String>) {
        guard cache.count > keep.count else { return }
        cache = cache.filter { keep.contains($0.key) }
    }

    public var cachedCount: Int { cache.count }

    // MARK: - Bounded read

    /// Last `bytes` of a file, trimmed forward to the first newline.
    ///
    /// The trim matters: a window starting mid-file begins with a fragment of
    /// JSON, and dropping it here means the parser never sees a half-line it
    /// would have to guess about.
    public static func tail(of path: String, bytes: Int) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let offset = end > UInt64(bytes) ? end - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd() else { return nil }
        if offset > 0, let newline = data.firstIndex(of: 0x0A) {
            data = data[data.index(after: newline)...]
        }
        return data
    }
}
