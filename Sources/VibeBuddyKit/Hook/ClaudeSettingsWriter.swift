import Foundation

/// The only thing in this app that writes `~/.claude/settings.json`.
///
/// That file belongs to the user. It is hand-edited, eleven kilobytes long, and
/// nothing here may reorder it, reformat it, or lose a key it does not
/// understand. Decision D6 and risk R1 both live in this type:
///
/// - **Re-read before every mutation.** No cache. The user may have edited the
///   file a second ago, and a stale copy written back is a silent revert.
/// - **A timestamped backup before the first write of a run**, so a wrong write
///   is repairable. Atomicity protects against a crash mid-write; it does
///   nothing about a write that was logically wrong.
/// - **`replaceItemAt`**, so a reader never sees a half-written file.
/// - **Order preserved**, via `OrderedJSON` — see its own note on why
///   `.sortedKeys` is not the answer.
public struct ClaudeSettingsWriter: Sendable {

    public enum Failure: Error, Equatable {
        case unreadable(String)
        case notAnObject
        case cannotBackUp(String)
        case cannotWrite(String)
    }

    public let path: String
    /// Where backups go. One per run, not one per write.
    public let backupDirectory: String

    public init(path: String? = nil, backupDirectory: String? = nil) {
        let home = NSHomeDirectory() as NSString
        self.path = path ?? home.appendingPathComponent(".claude/settings.json")
        self.backupDirectory = backupDirectory
            ?? (SupportDirectory.path as NSString).appendingPathComponent("backups")
    }

    /// Reads the file as it is on disk right now. A missing file is an empty
    /// object, not an error: installing a hook must work on a fresh machine.
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

    /// Re-reads, applies `change`, writes atomically. The whole contract in one
    /// call so no caller can perform half of it.
    ///
    /// `change` returning nil means "nothing to do" — and then nothing is
    /// written and no backup is taken. An install that is already correct must
    /// leave the file's modification date alone, or every launch looks like an
    /// edit to anything watching the file.
    @discardableResult
    public func mutate(_ change: (OrderedJSON) -> OrderedJSON?) throws -> Bool {
        let current = try read()
        guard let updated = change(current), updated != current else { return false }
        try backUp()
        try write(updated)
        return true
    }

    /// One backup per run of the app, named for the moment it was taken.
    ///
    /// Not one per write: a hundred backups of the same file is not a safety
    /// net, it is a haystack. The first write of a run is the one that could
    /// have been wrong.
    public func backUp() throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard !Self.backedUpThisRun.value else { return }
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
        Self.backedUpThisRun.value = true
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
            // `replaceItemAt` rather than `write(to:atomically:)`: the latter
            // drops the file's permissions and ownership on some paths, and
            // this one is not ours to re-create.
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            throw Failure.cannotWrite(error.localizedDescription)
        }
    }

    /// Reset between tests; in the app it stays false until the first write.
    public static func forgetBackupForTesting() { backedUpThisRun.value = false }

    private static let backedUpThisRun = Flag()
}

/// A process-wide flag, safe to touch from anywhere.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return flag }
        set { lock.lock(); flag = newValue; lock.unlock() }
    }
}
