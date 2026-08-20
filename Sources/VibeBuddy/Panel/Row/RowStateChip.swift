import SwiftUI
import VibeBuddyKit

/// The coarse state, as a word in its own colour. The dot on the row carries
/// the same colour for the scan across rows; the chip carries the word.
struct RowStateChip: View {
    let session: AgentSession
    let l10n: Strings

    var body: some View {
        let label = SessionStateStyle.label(session, l10n)
        let colour = SessionStateStyle.colour(session)
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colour)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(colour.opacity(0.16)))
            .fixedSize()
            .help(session.awaitingAnswer ? (session.question ?? l10n.alertWaiting) : label)
    }
}
