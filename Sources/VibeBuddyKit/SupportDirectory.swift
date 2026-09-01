import Foundation

public enum AppName {
    public static let display = "VibeBuddy"

    /// What the bundle says it is. Falls back to `0` outside a bundle — `--info` and the
    /// benches run from a bare binary, where `Bundle.main` has no version at all.
    public static var bundleVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}

/// Where the app keeps the files a user can edit.
public enum SupportDirectory {
    public static let name = AppName.display

    /// Directories this app used to live in, newest first.
    static let legacyNames = ["vibebuddy", "notch-buddy"]

    public static var path: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/\(name)")
    }

    static func legacyPath(_ name: String) -> String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/\(name)")
    }

    public enum Migration: Equatable, Sendable {
        case notNeeded
        case moved(from: String)
        case bothPresent(legacy: String)
        case failed(String)
    }

    /// When both exist the old one is left alone and reported — never merged.
    @discardableResult
    public static func migrate(using manager: FileManager = .default) -> Migration {
        for legacy in legacyNames {
            let outcome = migrate(from: legacyPath(legacy), to: path, using: manager)
            if outcome != .notNeeded { return outcome }
        }
        return .notNeeded
    }

    @discardableResult
    static func migrate(
        from old: String, to new: String, using manager: FileManager = .default
    ) -> Migration {
        guard manager.fileExists(atPath: old) else { return .notNeeded }
        // On a case-insensitive volume `vibebuddy` and `VibeBuddy` are the same
        // directory, and moving one onto the other fails.
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
