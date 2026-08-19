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

    /// Whether reaching this state is worth interrupting someone.
    public var isNotable: Bool { self == .finished || self == .failed }
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
    public let at: Date

    public init(
        sessionID: String, projectName: String, action: ToolAction,
        turnEnded: Bool, lastResultWasError: Bool, subagentsRunning: Int,
        isLive: Bool, at: Date
    ) {
        self.sessionID = sessionID; self.projectName = projectName
        self.action = action; self.turnEnded = turnEnded
        self.lastResultWasError = lastResultWasError
        self.subagentsRunning = subagentsRunning
        self.isLive = isLive; self.at = at
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
        /// **Not produced from the transcript.** A pending permission prompt is
        /// interactive and resolved before anything is written, so this arrives
        /// only once RFC-006 delivers hook events. Declared here so the alert
        /// surface does not have to change when it does.
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
