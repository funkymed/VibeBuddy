import Foundation

/// Version shown by the panel and the About page.
enum AppVersion {
    /// The one place to edit the version.
    static let number = "1.0.0"

    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? number
    }

    static var short: String { "v" + current }
}
