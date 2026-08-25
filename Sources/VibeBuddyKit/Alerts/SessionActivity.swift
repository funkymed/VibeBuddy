import Foundation

/// What a session is doing, as far as anyone watching needs to know.
public enum SessionActivity: String, Sendable, Equatable, CaseIterable {
    case idle
    case working
    case finished
    case failed
    /// Stopped until answered — unlike `finished`, which can wait indefinitely.
    case awaiting

    public var isNotable: Bool {
        self == .finished || self == .failed || self == .awaiting
    }
}

/// A single reading of a session's transcript.
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
public struct SessionAlert: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case finished
        case failed
        /// The agent is blocked asking for something.
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
