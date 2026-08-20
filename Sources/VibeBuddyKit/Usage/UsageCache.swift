import Foundation

/// Remembers the last good reading across launches, shown with its age. The
/// endpoint is rate limited (measured 2026-08-20: `429`, `retry-after: 0`), so a
/// launch inside a refusal has nothing to show for the whole backoff.
public struct UsageCache {

    // Not `Sendable`: `UserDefaults` is not. Only ever touched from `UsageState`,
    // which is `@MainActor`.

    public static let key = "vibebuddy.usage.last"

    /// Past this, a stored reading is dropped rather than shown: a five-hour
    /// window resets, so yesterday's reading is not stale, it is wrong.
    public static let maximumAge: TimeInterval = 5 * 3600

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(now: Date = Date()) -> ClaudeUsage? {
        guard let data = defaults.data(forKey: Self.key),
              let usage = try? JSONDecoder().decode(ClaudeUsage.self, from: data),
              now.timeIntervalSince(usage.fetchedAt) < Self.maximumAge
        else { return nil }
        return usage
    }

    public func save(_ usage: ClaudeUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}
