import Foundation

/// Maps a tool name and its input to a coarse action.
///
/// Pure and free of I/O so the danger heuristics can be tested exhaustively —
/// they are the part where a false positive is expensive. A buddy that panics at
/// `rm -rf .build` teaches the user to ignore it, which costs more than the
/// warning was ever worth.
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

    /// What the tool is being pointed at.
    ///
    /// This is the difference between a pill that says "editing" and one that
    /// says "editing NotchPanel.swift". The priority order is taken from the
    /// reference implementation, which had already worked out that every tool
    /// puts its subject under a different key and that there is no common one.
    ///
    /// Paths are reduced to their last component: the pill has ~64 pt for this,
    /// and a full path would be truncated to its least informative half.
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

    /// Human label for a tool, for the status slot.
    ///
    /// French, because it is user-facing — the codebase is English, the UI is not.
    public static func label(tool: String) -> String {
        switch tool.lowercased() {
        case "bash", "bashoutput": return "commande"
        case "edit", "multiedit":  return "édition"
        case "write":              return "écriture"
        case "read", "notebookread": return "lecture"
        case "glob":               return "recherche"
        case "grep":               return "recherche"
        case "ls":                 return "listage"
        case "webfetch":           return "web"
        case "websearch":          return "recherche web"
        case "task", "agent":      return "délégation"
        case "todowrite":          return "plan"
        case "exitplanmode":       return "plan"
        case "notebookedit":       return "notebook"
        case "askuserquestion":    return "question"
        default:                   return String(tool.lowercased().prefix(14))
        }
    }

    /// Commands worth widening the buddy's eyes at.
    ///
    /// Tuned for precision over recall on purpose. Every pattern below either
    /// destroys data outside the project or hands over the machine; anything
    /// merely untidy is left alone.
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

    /// Download piped straight into a shell — `curl … | sh`, `wget … | bash`.
    ///
    /// Matching the literal string `"curl | sh"` does not work: a real command
    /// carries a URL between the two, which is exactly the case a test caught.
    /// So the two halves are checked independently, on either side of a pipe.
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

    /// `rm -rf` is only alarming depending on what follows it.
    ///
    /// The reference implementation gets this right and it is worth keeping: the
    /// character *after* the target is checked, so `rm -rf .build` and
    /// `rm -rf ./node_modules` stay quiet while `rm -rf /` and `rm -rf ~` do not.
    /// Without that check every project cleanup trips the alarm.
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
