import Foundation

/// Where the app keeps the files a user can edit, and how it got there.
///
/// # The move, and why it is written down
///
/// The directory used to be named after an earlier product name. Renaming it in
/// the source alone would have looked like a clean rename and behaved like data
/// loss: the buddies in there are usually **symbolic links** into a working
/// copy, and the settings that point at them survive independently. An app that
/// silently stops seeing them is an app that lost them, from where the user
/// stands.
///
/// So the new location is the truth, the old one is moved once, and the move is
/// the whole migration: `moveItem` keeps symbolic links as links rather than
/// following them.
public enum AppName {

    /// The product name, as the user sees it. Interpolated everywhere rather
    /// than retyped: the same string lives in the panel, the settings window,
    /// the quit item and every exported `.buddy` header, and four copies of a
    /// name is four chances to ship three of them.
    public static let display = "VibeBuddy"
}

public enum SupportDirectory {

    public static let name = AppName.display

    /// Directories this app used to live in, newest first.
    ///
    /// `vibebuddy` is in the list because macOS volumes are usually
    /// case-insensitive and were not always: on a case-sensitive volume a
    /// lowercase directory and a capitalised one are two places, and the user's
    /// buddies are in the one they created first.
    static let legacyNames = ["vibebuddy", "notch-buddy"]

    public static var path: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/\(name)")
    }

    static func legacyPath(_ name: String) -> String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/\(name)")
    }

    /// What happened, so `--info` can say it rather than leave the user
    /// wondering where their buddies went.
    public enum Migration: Equatable, Sendable {
        case notNeeded
        case moved(from: String)
        case bothPresent(legacy: String)
        case failed(String)
    }

    /// Move the old directory to the new one, once, if nothing is in the way.
    ///
    /// Deliberately conservative: when both exist the old one is left alone and
    /// reported. Merging two trees is the kind of operation that is right in
    /// nine cases and destroys the tenth, and there is no reason to guess when a
    /// person can look.
    @discardableResult
    public static func migrate(using manager: FileManager = .default) -> Migration {
        for legacy in legacyNames {
            let outcome = migrate(from: legacyPath(legacy), to: path, using: manager)
            if outcome != .notNeeded { return outcome }
        }
        return .notNeeded
    }

    /// Same move, on paths the caller chooses.
    ///
    /// Exists so the tests exercise the real code on a temporary tree instead of
    /// on the developer's own `Application Support` — a migration test that runs
    /// against live data is a migration test nobody dares run twice.
    @discardableResult
    static func migrate(
        from old: String, to new: String, using manager: FileManager = .default
    ) -> Migration {
        guard manager.fileExists(atPath: old) else { return .notNeeded }
        // On a case-insensitive volume `vibebuddy` and `VibeBuddy` are the same
        // directory, and moving one onto the other fails. Same place, nothing
        // to do — and nothing to warn about either.
        if isSamePlace(old, new, using: manager) { return .notNeeded }
        if manager.fileExists(atPath: new) { return .bothPresent(legacy: old) }
        do {
            try manager.createDirectory(
                atPath: (new as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try manager.moveItem(atPath: old, toPath: new)
            return .moved(from: old)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Whether two paths name the same directory on disk.
    ///
    /// Compared by the file system's own identifier rather than by string:
    /// case, symbolic links and `/private` prefixes all make two spellings of
    /// one directory look like two directories.
    static func isSamePlace(
        _ a: String, _ b: String, using manager: FileManager = .default
    ) -> Bool {
        guard manager.fileExists(atPath: a), manager.fileExists(atPath: b) else { return false }
        let ids = [a, b].map { path -> AnyHashable? in
            let values = try? URL(fileURLWithPath: path)
                .resourceValues(forKeys: [.fileResourceIdentifierKey])
            return (values?.fileResourceIdentifier as? AnyHashable)
        }
        guard let first = ids[0], let second = ids[1] else { return false }
        return first == second
    }
}
