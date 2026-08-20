import SwiftUI
import VibeBuddyKit

/// The colour and the word for a session state. The ordering lives in
/// `SessionDisplayState`; this only maps it to the app's palette.
enum SessionStateStyle {
    static func colour(_ session: AgentSession) -> Color {
        colour(SessionDisplayState.of(session))
    }

    static func colour(_ state: SessionDisplayState) -> Color {
        switch state {
        case .awaiting: return .blue
        case .failed:   return .red
        case .working:  return .green
        case .finished: return .orange
        case .idle:     return PanelInk.tertiary
        case .ended:    return PanelInk.disabled
        }
    }

    static func label(_ session: AgentSession, _ l10n: Strings) -> String {
        switch SessionDisplayState.of(session) {
        case .awaiting: return l10n.stateAwaiting
        case .failed:   return l10n.stateFailed
        case .working:  return l10n.stateWorking
        case .finished: return l10n.stateFinished
        case .idle:     return l10n.stateIdle
        case .ended:    return l10n.stateEnded
        }
    }
}
