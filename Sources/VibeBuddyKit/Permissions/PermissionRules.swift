import Foundation

/// Reads and adds entries in `permissions.allow` of `~/.claude/settings.json`.
public struct PermissionRules: Sendable {
    public let writer: ClaudeSettingsWriter

    public init(writer: ClaudeSettingsWriter = ClaudeSettingsWriter()) {
        self.writer = writer
    }

    /// Everything currently granted, as written.
    public func granted() -> Set<String> {
        guard let settings = try? writer.read(),
              case let .array(rules)? = settings["permissions"]?["allow"]
        else { return [] }
        return Set(rules.compactMap { rule in
            if case let .string(text) = rule { return text }
            return nil
        })
    }

    /// What the file looks like now, and what it would look like with `rule` added.
    public func preview(adding rule: String) throws -> (before: OrderedJSON, after: OrderedJSON) {
        let before = try writer.read()
        return (before, Self.adding(rule, to: before))
    }

    /// The pure part, so the tests never touch a disk.
    public static func adding(_ rule: String, to settings: OrderedJSON) -> OrderedJSON {
        let permissions = settings["permissions"] ?? .object([])
        guard permissions.objectPairs != nil else {
            // Something that is not an object under `permissions`.
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

    /// Writes the rule.
    @discardableResult
    public func commit(adding rule: String) throws -> Bool {
        try writer.mutate { Self.adding(rule, to: $0) }
    }

    public static func rule(for model: PermissionRequestModel) -> String {
        model.suggestions.first ?? model.toolName
    }
}

/// A pending « toujours autoriser », waiting to be looked at.
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

    /// Builds the consent for a request, or nil when the rule is already granted — there
    /// is nothing to write, so there is nothing to consent to.
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
