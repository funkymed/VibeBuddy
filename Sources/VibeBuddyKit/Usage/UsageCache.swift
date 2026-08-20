import Foundation

/// Remembers the last good reading across launches.
///
/// # Why a reading survives the process
///
/// The endpoint is rate limited (measured 2026-08-20: `429`, `retry-after: 0`),
/// and a launch that lands inside a refusal has nothing to show for as long as
/// the backoff lasts — while Claude Code's own status line, reading a cache of
/// its own, shows the real number. Two surfaces disagreeing about the same fact
/// is worse than one of them being a few minutes old.
///
/// # And why it is shown with its age
///
/// A stale number presented as current is exactly the plausible-but-wrong
/// reading this product exists to replace. The panel says how old it is; the
/// value itself is real, and was real when it was fetched.
public struct UsageCache {

    // Not `Sendable`: `UserDefaults` is not, and pretending otherwise to satisfy
    // a protocol is how a data race gets a rubber stamp. The cache is only ever
    // touched from `UsageState`, which is `@MainActor`.

    public static let key = "vibebuddy.usage.last"

    /// Past this, a stored reading is dropped rather than shown.
    ///
    /// A five-hour window resets, so a reading from yesterday describes a window
    /// that no longer exists — it is not stale, it is wrong.
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
