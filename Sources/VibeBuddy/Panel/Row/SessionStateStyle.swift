import SwiftUI
import VibeBuddyKit

/// The colour and the word for a session state, shared so the dot and the chip
/// can never disagree.
enum SessionStateStyle {
    static func colour(_ session: AgentSession) -> Color {
        guard session.isLive else { return PanelInk.disabled }
        // A question outranks everything, including an error underneath it:
        // nothing moves until the user acts.
        if session.awaitingAnswer { return .blue }
        if session.lastResultWasError { return .red }
        if session.action != .none { return .green }
        if session.turnEnded { return .orange }
        return PanelInk.tertiary
    }

    static func label(_ session: AgentSession, _ l10n: Strings) -> String {
        guard session.isLive else { return l10n.stateEnded }
        if session.awaitingAnswer { return l10n.stateAwaiting }
        if session.lastResultWasError { return l10n.stateFailed }
        if session.action != .none { return l10n.stateWorking }
        if session.turnEnded { return l10n.stateFinished }
        return l10n.stateIdle
    }
}
