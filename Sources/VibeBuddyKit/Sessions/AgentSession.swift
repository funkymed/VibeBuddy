import Foundation

/// Named `Agent`, not `Claude`: v1 is Claude-only by explicit decision (risk R11).
public struct AgentSession: Sendable, Equatable, Identifiable {
    /// Primary key.
    public let id: String
    public let provider: AgentProvider
    public let cwd: String
    public let projectName: String
    public let model: String
    public let effort: String
    public let startedAt: Date
    public let lastActivity: Date
    /// Language-neutral key for the running tool.
    public let status: ToolLabel?
    public let action: ToolAction
    public let permissionMode: String
    public let contextTokens: Int
    /// 200k normally, 1M once a session has been observed above the threshold.
    public let contextWindow: Int
    /// Nil while the session is known from its transcript but unpaired to a process.
    public let pid: pid_t?
    public let subject: String?
    /// Read from `system/turn_duration`, not inferred from inactivity.
    public let turnEnded: Bool
    public let lastResultWasError: Bool
    public let subagentsRunning: Int
    public let awaitingAnswer: Bool
    public let question: String?
    public let isLive: Bool
    /// Where the transcript lives, so the timeline can be read without walking the
    /// corpus again. Empty for a session built by a test.
    public let transcriptPath: String

    public init(
        id: String, provider: AgentProvider = .claudeCode, cwd: String,
        projectName: String, model: String, effort: String = "",
        startedAt: Date, lastActivity: Date,
        status: ToolLabel?, action: ToolAction, permissionMode: String,
        contextTokens: Int, contextWindow: Int, pid: pid_t?, isLive: Bool,
        subject: String? = nil, turnEnded: Bool = false,
        lastResultWasError: Bool = false, subagentsRunning: Int = 0,
        awaitingAnswer: Bool = false, question: String? = nil,
        transcriptPath: String = ""
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
        self.transcriptPath = transcriptPath
    }

    public var contextFraction: Double {
        contextWindow > 0 ? min(1, Double(contextTokens) / Double(contextWindow)) : 0
    }
}

/// One case today, so adding Codex is a new case, not a hunt for hard-coded paths (R11).
public enum AgentProvider: String, Sendable, Equatable, CaseIterable {
    case claudeCode

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        }
    }
}

public enum ToolAction: String, Sendable, Equatable, CaseIterable {
    case none
    case reading
    case editing
    case shell
    /// A shell command matching a destructive pattern.
    case danger
    case web
    case delegating
    case planning
}

/// Untranslated key for the running tool.
public enum ToolLabel: Sendable, Equatable {
    case shell
    case editing
    case writing
    case reading
    case searching
    case listing
    case web
    case webSearch
    case delegating
    case planning
    case notebook
    case question
    /// A tool we do not know, carrying its own name.
    case other(String)
}
