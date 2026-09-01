import Foundation

/// What the newest published release is.
public struct LatestRelease: Sendable, Equatable {
    public let version: ReleaseVersion
    /// The page a person is sent to, never a binary this app downloads on its own.
    public let page: URL

    public init(version: ReleaseVersion, page: URL) {
        self.version = version
        self.page = page
    }
}

public enum ReleaseOutcome: Sendable, Equatable {
    case found(LatestRelease)
    /// Offline, rate-limited, unreadable: all one case on purpose. Nothing downstream
    /// behaves differently, and a failed update check has no business saying anything
    /// to anyone.
    case unavailable
}

/// Asks GitHub what the newest release is. Reads only; downloads nothing.
public actor ReleaseChecker {
    /// Unauthenticated, so 60 requests an hour per address. One a day leaves room.
    public static let endpoint = URL(
        string: "https://api.github.com/repos/funkymed/VibeBuddy/releases/latest")!

    private let url: URL
    private let session: URLSession

    public init(url: URL = ReleaseChecker.endpoint, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func fetch() async -> ReleaseOutcome {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Asked for by name: GitHub throttles unidentified clients harder, and an app
        // that polls somebody else's API owes them a way to see who is calling.
        request.setValue("VibeBuddy/\(AppName.bundleVersion)", forHTTPHeaderField: "User-Agent")
        // Shorter than the usage client's: nobody is waiting on this, and a check that
        // hangs holds a `URLSession` task for nothing.
        request.timeoutInterval = 8

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unavailable }

        // A draft has no business being offered, and a prerelease is not what `brew`
        // would install either.
        if json["draft"] as? Bool == true || json["prerelease"] as? Bool == true {
            return .unavailable
        }
        guard let tag = json["tag_name"] as? String,
              let version = ReleaseVersion(tag)
        else { return .unavailable }

        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/funkymed/VibeBuddy/releases/latest")!
        return .found(LatestRelease(version: version, page: page))
    }
}
