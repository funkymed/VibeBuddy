import Foundation

/// Not in the transcript: measured here, `~/.claude/settings.json` holds `"model":
/// "opus[1m]"` while all 3 000 entries of the matching transcript say plain
/// `claude-opus-5`.
public struct ContextWindowResolver: Sendable {
    static let largeWindowMarker = "[1m]"

    public static let defaultWindow = 200_000
    public static let largeWindow = 1_000_000

    private struct Entry {
        let stamps: [TimeInterval]
        let window: Int
    }

    private var cache: [String: Entry] = [:]
    private let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    private func files(forProject cwd: String) -> [String] {
        [
            (home as NSString).appendingPathComponent(".claude/settings.json"),
            (cwd as NSString).appendingPathComponent(".claude/settings.json"),
            (cwd as NSString).appendingPathComponent(".claude/settings.local.json"),
        ]
    }

    /// `mutating` for the cache: without it, three JSON parses per session per refresh.
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

    /// `env.ANTHROPIC_MODEL` counts too: it is the other supported way to pin a model.
    static func model(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let model = root["model"] as? String, !model.isEmpty { return model }
        if let env = root["env"] as? [String: Any],
           let model = env["ANTHROPIC_MODEL"] as? String, !model.isEmpty { return model }
        return nil
    }

    /// Read only the marker, never the family: a family-to-window table would have to
    /// track a product that ships new names faster than this app ships builds.
    public static func window(forModel model: String) -> Int {
        model.lowercased().contains(largeWindowMarker) ? largeWindow : defaultWindow
    }
}
