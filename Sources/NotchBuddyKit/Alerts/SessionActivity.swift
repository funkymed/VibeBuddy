import Foundation

/// What a session is doing, as far as anyone watching needs to know.
///
/// Deliberately coarser than `ToolAction`: that one drives an expression, this
/// one drives whether to *interrupt* someone. Four states is the whole
/// vocabulary an alert needs.
public enum SessionActivity: String, Sendable, Equatable, CaseIterable {
    /// Known, alive, nothing in flight.
    case idle
    /// A tool is running.
    case working
    /// The turn completed. The agent is waiting for the user — which is both
    /// "it finished" and "it wants you", the two things worth a notification.
    case finished
    /// The turn completed after a tool error.
    case failed
    /// The agent asked the user something and is stopped until it is answered.
    ///
    /// Distinct from `finished` on purpose: a finished turn can wait
    /// indefinitely without anyone losing anything, while an unanswered question
    /// is an agent standing still. Objective n°1 of the product names the two
    /// separately, so the model does too.
    case awaiting

    /// Whether reaching this state is worth interrupting someone.
    public var isNotable: Bool {
        self == .finished || self == .failed || self == .awaiting
    }
}

/// A single reading of a session's transcript.
///
/// The state machine consumes these rather than raw entries, so it can be
/// tested without any JSON at all.
public struct SessionObservation: Sendable, Equatable {
    public let sessionID: String
    public let projectName: String
    public let action: ToolAction
    public let turnEnded: Bool
    public let lastResultWasError: Bool
    public let subagentsRunning: Int
    public let isLive: Bool
    public let awaitingAnswer: Bool
    public let at: Date

    public init(
        sessionID: String, projectName: String, action: ToolAction,
        turnEnded: Bool, lastResultWasError: Bool, subagentsRunning: Int,
        isLive: Bool, at: Date, awaitingAnswer: Bool = false
    ) {
        self.sessionID = sessionID; self.projectName = projectName
        self.action = action; self.turnEnded = turnEnded
        self.lastResultWasError = lastResultWasError
        self.subagentsRunning = subagentsRunning
        self.isLive = isLive; self.at = at
        self.awaitingAnswer = awaitingAnswer
    }
}

/// Something worth telling the user about.
///
/// Named `SessionAlert` rather than `Alert` because SwiftUI already owns that
/// name, and an ambiguity that has to be qualified at every use site is worse
/// than a slightly longer name declared once.
public struct SessionAlert: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        /// The agent finished its turn and is waiting.
        case finished
        /// The turn ended after an error.
        case failed
        /// The agent is blocked asking for something.
        ///
        /// **Produced from the transcript** since 2026-08-20, for the tools
        /// that are questions by definition — `AskUserQuestion`, `ExitPlanMode`.
        /// A `tool_use` of one of those with no `tool_result` behind it is an
        /// agent standing still, and that is readable without any hook.
        ///
        /// What still needs RFC-006 is a pending *permission* prompt: it is
        /// resolved interactively and written only once it is over, so nothing
        /// in the file says it is happening while it is happening.
        case needsAttention
    }

    public let id: UUID
    public let sessionID: String
    public let projectName: String
    public let kind: Kind
    public let at: Date

    public init(
        id: UUID = UUID(), sessionID: String, projectName: String,
        kind: Kind, at: Date
    ) {
        self.id = id; self.sessionID = sessionID
        self.projectName = projectName; self.kind = kind; self.at = at
    }
}
