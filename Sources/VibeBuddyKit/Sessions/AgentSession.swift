import Foundation

/// A live coding-agent session.
///
/// Named `Agent`, not `Claude`, deliberately. The v1 only speaks Claude Code —
/// that is an explicit decision (risk R11), not an oversight — but the type
/// names are the cheap half of that decision. Renaming a model after it has
/// spread through five modules is what actually costs; calling it the right
/// thing today costs nothing.
public struct AgentSession: Sendable, Equatable, Identifiable {

    /// Primary key: the transcript file's own session id. `cwd` is a secondary
    /// index only — two agents can share a directory, and the reference
    /// implementation's habit of matching on `cwd` is exactly why it pairs
    /// sessions with the wrong process.
    public let id: String
    public let provider: AgentProvider
    public let cwd: String
    public let projectName: String
    public let model: String
    /// Reasoning effort — `high`, `medium`… Empty when the agent does not report one.
    public let effort: String
    public let startedAt: Date
    public let lastActivity: Date
    public let status: String
    public let action: ToolAction
    public let permissionMode: String
    /// Prompt tokens on the last turn — the context window as the agent sees it.
    public let contextTokens: Int
    /// 200k normally, 1M once a session has been observed above the threshold.
    public let contextWindow: Int
    /// Resolved from `libproc`. Nil while the session is known from its
    /// transcript but no matching process has been paired to it yet.
    public let pid: pid_t?
    /// What the tool is pointed at — a file name, a command, a pattern.
    public let subject: String?
    /// The turn completed: the agent is done and waiting for the user.
    /// Read from `system/turn_duration`, not inferred from inactivity.
    public let turnEnded: Bool
    /// The most recent tool result came back as an error (`is_error`).
    public let lastResultWasError: Bool
    /// Subagents still in flight. A subagent finishing is not the turn
    /// finishing, and conflating them would alert on every delegation.
    public let subagentsRunning: Int
    /// The agent asked a question and is stopped until it is answered.
    public let awaitingAnswer: Bool
    /// The question itself, when the tool carried one.
    public let question: String?
    /// True while a process is actually running this session. A transcript with
    /// a fresh mtime proves nothing: a cleanly exited session leaves one behind.
    public let isLive: Bool

    public init(
        id: String, provider: AgentProvider = .claudeCode, cwd: String,
        projectName: String, model: String, effort: String = "",
        startedAt: Date, lastActivity: Date,
        status: String, action: ToolAction, permissionMode: String,
        contextTokens: Int, contextWindow: Int, pid: pid_t?, isLive: Bool,
        subject: String? = nil, turnEnded: Bool = false,
        lastResultWasError: Bool = false, subagentsRunning: Int = 0,
        awaitingAnswer: Bool = false, question: String? = nil
    ) {
        self.id = id; self.provider = provider; self.cwd = cwd
        self.projectName = projectName; self.model = model; self.effort = effort
        self.startedAt = startedAt; self.lastActivity = lastActivity
        self.status = status; self.action = action
        self.permissionMode = permissionMode
        self.contextTokens = contextTokens; self.contextWindow = contextWindow
        self.pid = pid; self.isLive = isLive
        self.subject = subject; self.turnEnded = turnEnded
        self.lastResultWasError = lastResultWasError
        self.subagentsRunning = subagentsRunning
        self.awaitingAnswer = awaitingAnswer
        self.question = question
    }

    public var contextFraction: Double {
        contextWindow > 0 ? min(1, Double(contextTokens) / Double(contextWindow)) : 0
    }
}

/// Which agent a session belongs to.
///
/// One case today. It exists so that adding Codex or Copilot is a new case and a
/// new provider implementation, rather than a hunt through five modules for
/// hard-coded paths — see R11.
public enum AgentProvider: String, Sendable, Equatable, CaseIterable {
    case claudeCode

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        }
    }
}

/// What the agent is doing right now, coarse enough to drive an expression.
public enum ToolAction: String, Sendable, Equatable, CaseIterable {
    case none
    case reading
    case editing
    case shell
    /// A shell command matching a destructive pattern.
    case danger
    case thinking
    case web
    case delegating
    case planning
}
