import Foundation

/// Transcripts grow without bound — 8 MB for a day's work, 517 files in the corpus here.
public struct JSONLTailReader: Sendable {
    public static let windowBytes = 64 * 1024

    private struct Cached {
        let modified: Date
        let size: UInt64
        let parsed: ParsedTail
    }

    private var cache: [String: Cached] = [:]

    public init() {}

    /// Keyed on mtime *and* size: compaction rewrites a transcript in place keeping its
    /// size, and a file can change size within the same second.
    public mutating func read(path: String, modified: Date, size: UInt64) -> ParsedTail? {
        if let hit = cache[path], hit.modified == modified, hit.size == size {
            return hit.parsed
        }
        guard let data = Self.tail(of: path, bytes: Self.windowBytes) else { return nil }
        let parsed = TranscriptParser.parse(data)
        cache[path] = Cached(modified: modified, size: size, parsed: parsed)
        return parsed
    }

    /// Claude Code never deletes a transcript: without eviction this grows forever.
    public mutating func evict(keeping keep: Set<String>) {
        guard cache.count > keep.count else { return }
        cache = cache.filter { keep.contains($0.key) }
    }

    public var cachedCount: Int { cache.count }

    /// Trimmed forward past the first newline: a mid-file window opens on a JSON
    /// fragment.
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
