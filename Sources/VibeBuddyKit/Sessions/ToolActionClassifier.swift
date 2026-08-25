import Foundation

public enum ToolActionClassifier {
    public static func classify(tool: String, input: [String: Any]) -> ToolAction {
        switch tool {
        case "Read", "Grep", "Glob", "LS", "NotebookRead":
            return .reading
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return .editing
        case "WebFetch", "WebSearch":
            return .web
        case "Task", "Agent":
            return .delegating
        case "TodoWrite", "ExitPlanMode":
            return .planning
        case "Bash", "BashOutput":
            let command = (input["command"] as? String) ?? ""
            return isDangerous(command) ? .danger : .shell
        default:
            return .none
        }
    }

    /// Every tool puts its subject under a different key; there is no common one. Paths
    /// reduce to their last component: the pill has ~64 pt and truncates the rest.
    public static func subject(tool: String, input: [String: Any]) -> String? {
        if let command = input["command"] as? String, !command.isEmpty {
            return String(command.prefix(80))
        }
        if let path = input["file_path"] as? String, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        if let pattern = input["pattern"] as? String, !pattern.isEmpty { return pattern }
        if let url = input["url"] as? String, !url.isEmpty { return url }
        if let query = input["query"] as? String, !query.isEmpty { return query }
        if let questions = input["questions"] as? [[String: Any]],
           let first = questions.first,
           let question = first["question"] as? String, !question.isEmpty {
            return String(question.prefix(80))
        }
        if let description = input["description"] as? String, !description.isEmpty {
            return String(description.prefix(80))
        }
        return nil
    }

    /// Returns a key, never a sentence: this type lives in the Kit and must not decide
    /// the interface language.
    public static func label(tool: String) -> ToolLabel {
        switch tool.lowercased() {
        case "bash", "bashoutput":   return .shell
        case "edit", "multiedit":    return .editing
        case "write":                return .writing
        case "read", "notebookread": return .reading
        case "glob", "grep":         return .searching
        case "ls":                   return .listing
        case "webfetch":             return .web
        case "websearch":            return .webSearch
        case "task", "agent":        return .delegating
        case "todowrite", "exitplanmode": return .planning
        case "notebookedit":         return .notebook
        case "askuserquestion":      return .question
        default:                     return .other(String(tool.lowercased().prefix(14)))
        }
    }

    /// Commands worth widening the buddy's eyes at.
    public static func isDangerous(_ command: String) -> Bool {
        let c = command.lowercased()

        // Fork bomb, in its usual spelling and with whitespace variations.
        if c.replacingOccurrences(of: " ", with: "").contains(":(){:|:&};:") { return true }

        for pattern in destructivePatterns where c.contains(pattern) { return true }
        if pipesDownloadToShell(c) { return true }
        if hasDangerousRemoval(c) { return true }
        return false
    }

    private static let destructivePatterns = [
        "mkfs", "dd if=/dev/", "> /dev/sd", "chmod -r 777 /",
        "drop table", "drop database", "truncate table",
        "shutdown ", "reboot ", "diskutil erase",
        "git push --force origin main", "git push -f origin main",
        "history -c",
    ]

    private static func pipesDownloadToShell(_ c: String) -> Bool {
        let parts = c.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let fetchers = ["curl", "wget", "fetch"]
        let shells = ["sh", "bash", "zsh", "python", "python3", "ruby", "perl", "node"]
        guard fetchers.contains(where: { parts[0].contains($0) }) else { return false }
        for downstream in parts.dropFirst() {
            let first = downstream.split(separator: " ").first.map(String.init) ?? ""
            let bare = first.split(separator: "/").last.map(String.init) ?? first
            if shells.contains(bare) { return true }
        }
        return false
    }

    /// `rm -rf` is only alarming depending on what follows.
    private static func hasDangerousRemoval(_ c: String) -> Bool {
        guard c.contains("rm ") else { return false }
        let recursive = c.contains("-rf") || c.contains("-fr")
            || (c.contains("-r") && c.contains("-f"))
        guard recursive else { return false }

        for target in ["/", "~", "$home", "/*", "/users", "/system", "/library", "/applications"] {
            guard let range = c.range(of: "rm ") else { continue }
            let tail = c[range.upperBound...]
            // Skip the flags to reach the first operand.
            let operand = tail.split(separator: " ").first { !$0.hasPrefix("-") }
            guard let operand else { continue }
            if operand == target { return true }
            // `/usr`, `/etc`… — a bare absolute path outside the working tree.
            if target == "/" && operand.hasPrefix("/") && operand.split(separator: "/").count <= 2 {
                return true
            }
        }
        return c.contains("sudo rm")
    }
}
