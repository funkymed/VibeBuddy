import Foundation

/// Reads and adds entries in `permissions.allow` of `~/.claude/settings.json`.
///
/// The file is the user's, and this is the second thing in the app allowed to
/// write it — through `ClaudeSettingsWriter`, like the first (decision D6, risk
/// R1). Everything that made the hook installer safe applies here unchanged:
/// re-read before every mutation, a timestamped backup, an atomic replace, and
/// the order of the user's own keys preserved. RFC-007, T7.
///
/// **Nothing here writes without being shown first.** `preview(adding:)` hands
/// back the before and after so the consent screen can diff them; `commit` is a
/// separate call. Splitting them is the whole of T8: an "always allow" that
/// silently edits a file nobody looked at is the failure R1 describes.
public struct PermissionRules: Sendable {

    public let writer: ClaudeSettingsWriter

    public init(writer: ClaudeSettingsWriter = ClaudeSettingsWriter()) {
        self.writer = writer
    }

    /// Everything currently granted, as written.
    ///
    /// Read fresh on every call, never cached: the user edits this file by
    /// hand, and a stale copy grants something they may have just taken back.
    /// An unreadable file reads as "nothing granted" rather than throwing —
    /// failing to *grant* is safe, and the caller is a permission prompt that
    /// must still work.
    public func granted() -> Set<String> {
        guard let settings = try? writer.read(),
              case let .array(rules)? = settings["permissions"]?["allow"]
        else { return [] }
        return Set(rules.compactMap { rule in
            if case let .string(text) = rule { return text }
            return nil
        })
    }

    /// What the file looks like now, and what it would look like with `rule`
    /// added. Equal values mean the rule is already there.
    ///
    /// `permissions` and `allow` are created when missing, in that order, and
    /// **appended to** rather than replaced: `OrderedJSON.setting` puts a key
    /// back where it stood, so a file that had `allow` third keeps it third.
    public func preview(adding rule: String) throws -> (before: OrderedJSON, after: OrderedJSON) {
        let before = try writer.read()
        return (before, Self.adding(rule, to: before))
    }

    /// The pure part, so the tests never touch a disk.
    public static func adding(_ rule: String, to settings: OrderedJSON) -> OrderedJSON {
        let permissions = settings["permissions"] ?? .object([])
        guard permissions.objectPairs != nil else {
            // Something that is not an object under `permissions`. Not ours to
            // reinterpret — the file is left exactly as it was.
            return settings
        }

        var rules: [OrderedJSON]
        switch permissions["allow"] {
        case let .array(existing)?: rules = existing
        case .none: rules = []
        // Nor is a non-array `allow`.
        default: return settings
        }

        guard !rules.contains(.string(rule)) else { return settings }
        rules.append(.string(rule))
        return settings.setting(
            "permissions", to: permissions.setting("allow", to: .array(rules)))
    }

    /// Writes the rule. Returns false when there was nothing to write.
    ///
    /// The mutation is applied by re-reading inside `ClaudeSettingsWriter`, not
    /// by writing back the `after` a preview produced: between the two the user
    /// may have edited the file, and writing a value computed against an older
    /// copy is a silent revert of whatever they did.
    @discardableResult
    public func commit(adding rule: String) throws -> Bool {
        try writer.mutate { Self.adding(rule, to: $0) }
    }

    /// The rule to offer for a request.
    ///
    /// Claude Code's own suggestion wins whenever it made one: it is written in
    /// its pattern language, which this app deliberately does not parse, and it
    /// is scoped to what was actually asked (`Bash(npm install:*)` rather than
    /// every `Bash` for ever). The bare tool name is the fallback, and it is a
    /// far broader grant — which is why it is never preferred.
    public static func rule(for model: PermissionRequestModel) -> String {
        model.suggestions.first ?? model.toolName
    }
}

/// A pending « toujours autoriser », waiting to be looked at. RFC-007, T8.
///
/// Carries the diff rather than the two documents: the consent screen shows it
/// and nothing else, and holding the whole file twice for a screenful of lines
/// is the sort of thing this app has measured the cost of before.
public struct PermissionConsent: Sendable, Equatable {
    public let requestID: String
    public let rule: String
    public let diff: String
    public let backupDirectory: String

    public init(requestID: String, rule: String, diff: String, backupDirectory: String) {
        self.requestID = requestID
        self.rule = rule
        self.diff = diff
        self.backupDirectory = backupDirectory
    }

    /// Builds the consent for a request, or nil when the rule is already
    /// granted — there is nothing to write, so there is nothing to consent to.
    public static func make(
        for model: PermissionRequestModel, rules: PermissionRules
    ) -> PermissionConsent? {
        let rule = PermissionRules.rule(for: model)
        guard let (before, after) = try? rules.preview(adding: rule), after != before
        else { return nil }
        return PermissionConsent(
            requestID: model.id, rule: rule,
            diff: TextDiff.unified(before.encoded(), after.encoded()),
            backupDirectory: rules.writer.backupDirectory)
    }
}
