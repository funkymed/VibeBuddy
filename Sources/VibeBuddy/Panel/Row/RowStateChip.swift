import SwiftUI
import VibeBuddyKit

/// The coarse state, as a word in its own colour.
struct RowStateChip: View {
    let session: AgentSession
    let l10n: Strings

    var body: some View {
        let label = SessionStateStyle.label(session, l10n)
        let colour = SessionStateStyle.colour(session)
        VibeBadge(text: label, tint: colour)
            .help(session.awaitingAnswer ? (session.question ?? l10n.alertWaiting) : label)
    }
}
