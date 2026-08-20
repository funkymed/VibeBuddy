import Foundation

/// Which context window a session is running with.
///
/// # Why this is not in the transcript
///
/// Every assistant entry carries `"model":"claude-opus-5"` and nothing else.
/// The `[1m]` that selects the million-token window lives in the *settings*, not
/// in the messages — measured on this machine: `~/.claude/settings.json` holds
/// `"model": "opus[1m]"`, while every one of the 3 000 entries of the matching
/// transcript says plain `claude-opus-5`.
///
/// So the window cannot be read where the tokens are read. It is a fact about
/// the configuration, and this is the one place that answers it — D1 applies to
/// the window as much as to anything else.
///
/// # What it costs
///
/// Three `stat` calls per resolution, and a parse only when one of the files has
/// actually changed. Nothing here runs at rest: the store asks while it is
/// already walking transcripts.
///
/// # What it cannot know
///
/// A `/model` typed mid-session, or `--model` on the command line, overrides the
/// settings and leaves no trace anywhere we can see. The token threshold below
/// still catches those the moment they pass 200k — late, but never wrong in the
/// other direction: a session over 200k tokens cannot be running a 200k window.
public struct ContextWindowResolver: Sendable {

    /// Suffix Claude Code appends to a model name to ask for the large window.
    static let largeWindowMarker = "[1m]"

    public static let defaultWindow = 200_000
    public static let largeWindow = 1_000_000

    /// One remembered answer, with the file stamps it was computed from.
    private struct Entry {
        let stamps: [TimeInterval]
        let window: Int
    }

    private var cache: [String: Entry] = [:]
    /// Overridable so tests do not depend on the developer's own settings.
    private let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    /// Settings files that decide the model, weakest first — the last one that
    /// names a model wins, which is Claude Code's own precedence.
    private func files(forProject cwd: String) -> [String] {
        [
            (home as NSString).appendingPathComponent(".claude/settings.json"),
            (cwd as NSString).appendingPathComponent(".claude/settings.json"),
            (cwd as NSString).appendingPathComponent(".claude/settings.local.json"),
        ]
    }

    /// The window for a session running in `cwd`.
    ///
    /// `mutating` because the cache is the whole point: without it this parses
    /// three JSON files per session per refresh, which is exactly the kind of
    /// quiet cost this project measures.
    public mutating func window(forProject cwd: String) -> Int {
        let paths = files(forProject: cwd)
        let stamps = paths.map { path -> TimeInterval in
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }
        if let cached = cache[cwd], cached.stamps == stamps { return cached.window }

        var window = Self.defaultWindow
        for path in paths {
            guard let model = Self.model(atPath: path) else { continue }
            window = Self.window(forModel: model)
        }
        cache[cwd] = Entry(stamps: stamps, window: window)
        return window
    }

    /// The `model` a settings file names, or nil if it names none.
    ///
    /// `env.ANTHROPIC_MODEL` counts too: it is the other supported way to pin a
    /// model, and a file that sets it means it just as much as one setting
    /// `model` directly.
    static func model(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let model = root["model"] as? String, !model.isEmpty { return model }
        if let env = root["env"] as? [String: Any],
           let model = env["ANTHROPIC_MODEL"] as? String, !model.isEmpty { return model }
        return nil
    }

    /// A model name to a window.
    ///
    /// Only the marker is read, never the family: guessing a window from
    /// "opus" or "sonnet" would be a table to keep in sync with a product that
    /// ships new names faster than this app ships builds, and being silently
    /// wrong is the failure this whole change exists to fix.
    public static func window(forModel model: String) -> Int {
        model.lowercased().contains(largeWindowMarker) ? largeWindow : defaultWindow
    }
}
