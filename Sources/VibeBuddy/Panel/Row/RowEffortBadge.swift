import SwiftUI
import VibeBuddyKit

struct RowEffortBadge: View {
    let session: AgentSession

    var body: some View {
        // Purple, and purple is used nowhere else: an unusually expensive run is worth
        // recognising at a glance, and a colour that appears once is what makes that
        // possible.
        VibeBadge(text: session.effort,
                  tint: session.effort == "high" ? .purple.opacity(0.95) : nil)
    }
}
