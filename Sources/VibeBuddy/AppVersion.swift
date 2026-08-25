import Foundation

/// Version shown by the panel and the About page. An unbundled executable has
/// no `Info.plist`, so `number` below is what ships until RFC-011 lands.
enum AppVersion {

    /// The one place to edit the version.
    static let number = "0.4.3"

    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? number
    }

    static var short: String { "v" + current }
}
