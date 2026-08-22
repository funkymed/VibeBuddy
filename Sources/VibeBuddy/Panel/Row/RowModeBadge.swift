import SwiftUI
import VibeBuddyKit

/// The permission mode the session runs under.
struct RowModeBadge: View {
    let session: AgentSession

    var body: some View {
        VibeBadge(text: session.permissionMode)
    }
}
