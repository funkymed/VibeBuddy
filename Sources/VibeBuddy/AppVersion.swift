import Foundation

/// The version the panel and the About page display.
///
/// # Where to change it
///
/// Here, in `number`, and nowhere else — until RFC-011 produces a bundle.
///
/// `Bundle.main.infoDictionary` is the right source for a packaged app, and it
/// is empty for the bare binary this currently is: an unbundled executable has
/// no `Info.plist`, so `CFBundleShortVersionString` is nil and the constant
/// below is what ships. Reading the bundle first means the day the `.app`
/// exists, the plist wins with no code change; the constant stays as the
/// fallback for anyone running from the build directory.
///
/// Keeping both in step is a release step, not a build step — `build.sh` will
/// write the plist from this constant when RFC-011 lands (T3).
enum AppVersion {

    /// Semantic version of the app. **The one place to edit.**
    static let number = "0.1.0"

    /// What the bundle says, or the constant above.
    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? number
    }

    /// Prefixed, for display: `v0.1.0`.
    static var short: String { "v" + current }
}
