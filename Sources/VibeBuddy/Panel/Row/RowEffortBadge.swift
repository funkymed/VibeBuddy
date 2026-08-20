import SwiftUI
import VibeBuddyKit

/// Reasoning effort. Coloured only when unusually high.
struct RowEffortBadge: View {
    let session: AgentSession

    var body: some View {
        Text(session.effort)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(session.effort == "high" ? .purple.opacity(0.95) : PanelInk.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(
                session.effort == "high" ? .purple.opacity(0.18) : PanelInk.stroke))
    }
}
