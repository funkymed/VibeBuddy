import Foundation

/// The permission mode a session runs under, when the transcript tail does not say.
///
/// A transcript carries `permissionMode` on its own entries, but the tail is 80 lines:
/// a long tool run pushes the last one out of the window, and the badge would blink off
/// and back for a session whose mode never changed.
///
/// The user file wins over the project's, which is measured behaviour rather than a
/// guess: `permissions.defaultMode` in `~/.claude/settings.json` overrides both
/// `--settings` and `--permission-mode` on the command line.
public struct PermissionModeResolver: Sendable {
    private struct Entry {
        let stamps: [TimeInterval]
        let mode: String
    }

    private var cache: [String: Entry] = [:]
    private let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    /// Least specific last, because the least specific is the one that wins here.
    private func files(forProject cwd: String) -> [String] {
        [
            (cwd as NSString).appendingPathComponent(".claude/settings.local.json"),
            (cwd as NSString).appendingPathComponent(".claude/settings.json"),
            (home as NSString).appendingPathComponent(".claude/settings.json"),
        ]
    }

    /// Empty when nothing declares one. The column stays reserved either way: a mode we
    /// cannot read is not a mode we may invent.
    public mutating func mode(forProject cwd: String) -> String {
        let paths = files(forProject: cwd)
        let stamps = paths.map { path -> TimeInterval in
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        }
        if let cached = cache[cwd], cached.stamps == stamps { return cached.mode }

        var mode = ""
        for path in paths {
            guard let found = Self.defaultMode(atPath: path) else { continue }
            mode = found
        }
        cache[cwd] = Entry(stamps: stamps, mode: mode)
        return mode
    }

    static func defaultMode(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let permissions = root["permissions"] as? [String: Any],
              let mode = permissions["defaultMode"] as? String,
              !mode.isEmpty
        else { return nil }
        return mode
    }
}
