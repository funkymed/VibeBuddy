import Foundation

/// The only thing in this app that writes `~/.claude/settings.json`.
public struct ClaudeSettingsWriter: Sendable {
    public enum Failure: Error, Equatable {
        case unreadable(String)
        case notAnObject
        case cannotBackUp(String)
        case cannotWrite(String)
    }

    public let path: String
    /// Where backups go.
    public let backupDirectory: String

    public init(path: String? = nil, backupDirectory: String? = nil) {
        let home = NSHomeDirectory() as NSString
        self.path = path ?? home.appendingPathComponent(".claude/settings.json")
        self.backupDirectory = backupDirectory
            ?? (SupportDirectory.path as NSString).appendingPathComponent("backups")
    }

    /// Reads the file as it is on disk right now.
    public func read() throws -> OrderedJSON {
        guard let data = FileManager.default.contents(atPath: path) else {
            return .object([])
        }
        guard !data.isEmpty else { return .object([]) }
        let value: OrderedJSON
        do { value = try OrderedJSON.parse(data) }
        catch { throw Failure.unreadable("\(error)") }
        guard value.objectPairs != nil else { throw Failure.notAnObject }
        return value
    }

    /// Re-reads, applies `change`, writes atomically.
    @discardableResult
    public func mutate(_ change: (OrderedJSON) -> OrderedJSON?) throws -> Bool {
        let current = try read()
        guard let updated = change(current), updated != current else { return false }
        try backUp()
        try write(updated)
        return true
    }

    /// One backup per run of the app, named for the moment it was taken.
    public func backUp() throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard !Self.backedUp.contains(path) else { return }
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let name = "settings-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "")).json"
        let destination = (backupDirectory as NSString).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(
                atPath: backupDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination) {
                try FileManager.default.removeItem(atPath: destination)
            }
            try FileManager.default.copyItem(atPath: path, toPath: destination)
        } catch {
            throw Failure.cannotBackUp(error.localizedDescription)
        }
        Self.backedUp.insert(path)
    }

    private func write(_ value: OrderedJSON) throws {
        let text = value.encoded() + "\n"
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = url.deletingLastPathComponent()
                .appendingPathComponent(".settings-\(UUID().uuidString).json")
            try Data(text.utf8).write(to: temporary)
            // `replaceItemAt` rather than `write(to:atomically:)`: the latter drops the
            // file's permissions and ownership on some paths, and this one is not ours
            // to re-create.
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            throw Failure.cannotWrite(error.localizedDescription)
        }
    }

    /// Reset between tests; in the app nothing ever clears it.
    public static func forgetBackupForTesting() { backedUp.removeAll() }

    /// Which files have been backed up this run.
    private static let backedUp = PathSet()
}

/// A process-wide set of paths, safe to touch from anywhere.
private final class PathSet: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []

    func contains(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return paths.contains(path)
    }

    func insert(_ path: String) {
        lock.lock(); paths.insert(path); lock.unlock()
    }

    func removeAll() {
        lock.lock(); paths.removeAll(); lock.unlock()
    }
}
