import SwiftUI
import VibeBuddyKit

/// The permission mode the session runs under.
struct RowModeBadge: View {
    let session: AgentSession

    var body: some View {
        Text(session.permissionMode)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(PanelInk.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(PanelInk.stroke))
    }
}
