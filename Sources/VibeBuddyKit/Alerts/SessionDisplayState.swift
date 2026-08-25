import Foundation

/// The single ordering of session states for the whole app.
public enum SessionDisplayState: String, Sendable, CaseIterable {
    /// The process is gone: history, not something to act on.
    case ended
    /// A question is on screen, nothing moves until the user answers.
    case awaiting
    case failed
    case working
    case finished
    case idle

    /// Urgency order, most urgent first.
    private static let urgency: [SessionDisplayState] = [.awaiting, .failed, .working, .finished, .idle]

    public static func of(_ session: AgentSession) -> SessionDisplayState {
        guard session.isLive else { return .ended }
        if session.awaitingAnswer { return .awaiting }
        if session.lastResultWasError { return .failed }
        // A session that delegates is working, not resting: the three non-Kit sites
        // used to forget `subagentsRunning` and report it idle.
        if session.action != .none || session.subagentsRunning > 0 { return .working }
        if session.turnEnded { return .finished }
        return .idle
    }

    /// What the collapsed pill shows, which is not the most *urgent* state.
    public static func onThePill(of sessions: [AgentSession]) -> SessionDisplayState? {
        let states = sessions.map(of)
        if states.contains(.working) { return .working }
        return aggregate(of: sessions)
    }

    /// Nil when nothing is alive.
    public static func aggregate(of sessions: [AgentSession]) -> SessionDisplayState? {
        var best = urgency.count
        for session in sessions {
            let state = of(session)
            guard let rank = urgency.firstIndex(of: state) else { continue }
            best = min(best, rank)
        }
        return best < urgency.count ? urgency[best] : nil
    }

    /// Bridge to the older vocabulary `BuddyExpression.from` speaks.
    public var activity: SessionActivity? {
        switch self {
        case .ended:    return nil
        case .awaiting: return .awaiting
        case .failed:   return .failed
        case .working:  return .working
        case .finished: return .finished
        case .idle:     return .idle
        }
    }
}
