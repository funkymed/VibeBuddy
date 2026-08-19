import Foundation

/// Reads the OAuth token and asks Anthropic for the real numbers.
///
/// # The keychain detour
///
/// The obvious call is `SecItemCopyMatching`. It is the wrong one: the
/// `Claude Code-credentials` item carries an ACL listing the binaries allowed to
/// read it, and `/usr/bin/security` is on that list *because Claude Code used
/// that binary to write the token in the first place*. Reading through the same
/// path succeeds silently; reading from our own binary presents a different
/// identity and prompts the user for their login password.
///
/// Verified on 2026-08-19: the token reads with no prompt, and the endpoint
/// answers 200 in 0.32 s.
///
/// This depends on an implementation detail of another program (risk R4), so it
/// sits behind `CredentialSource` — replacing it is one file, not a hunt.
///
/// # No refreshing, ever
///
/// Claude Code owns the refresh token and rewrites the keychain itself. A second
/// refresher racing it is how a user gets signed out.
public actor UsageClient {

    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Dated on purpose, and unstable by nature — see R5.
    public static let betaHeader = "oauth-2025-04-20"

    private let credentials: CredentialSource
    private let session: URLSession
    /// Cached until it expires, so a refresh does not fork `security` every time.
    private var cachedToken: (value: String, expiresAt: Date)?

    public init(credentials: CredentialSource = KeychainCredentials(), session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func fetch(now: Date = Date()) async -> UsageOutcome {
        guard let token = token(now: now) else { return .noCredentials }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("réponse illisible") }

            if http.statusCode == 429 {
                let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 60
                return .rateLimited(retryAfter: retry)
            }
            if http.statusCode == 401 {
                // The cached token outlived its usefulness; drop it so the next
                // attempt re-reads whatever Claude Code has written since.
                cachedToken = nil
                return .noCredentials
            }
            guard http.statusCode == 200 else { return .failed("HTTP \(http.statusCode)") }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failed("JSON illisible")
            }
            return .success(ClaudeUsage.parse(json, now: now))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func token(now: Date) -> String? {
        if let cached = cachedToken, cached.expiresAt > now { return cached.value }
        guard let fresh = credentials.read(), fresh.expiresAt > now else { return nil }
        cachedToken = (fresh.token, fresh.expiresAt)
        return fresh.token
    }
}

/// Where the OAuth token comes from.
///
/// A protocol with one real implementation, so the keychain hack can be swapped
/// without touching anything else the day Anthropic changes how it stores
/// credentials — and so tests never touch the real keychain.
public protocol CredentialSource: Sendable {
    func read() -> (token: String, expiresAt: Date)?
}

public struct KeychainCredentials: CredentialSource {
    public init() {}

    public func read() -> (token: String, expiresAt: Date)? {
        // The account-scoped entry holds refreshed tokens; the null-account one
        // dates from the initial login. Newest first.
        readEntry(account: NSUserName()) ?? readEntry(account: nil)
    }

    private func readEntry(account: String?) -> (token: String, expiresAt: Date)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        var arguments = ["find-generic-password", "-s", "Claude Code-credentials"]
        if let account { arguments += ["-a", account] }
        arguments.append("-w")
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              // Milliseconds since the epoch, not seconds.
              let expiresMs = oauth["expiresAt"] as? Double
        else { return nil }

        return (token, Date(timeIntervalSince1970: expiresMs / 1000))
    }
}
