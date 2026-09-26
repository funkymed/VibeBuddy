import SwiftUI
import VibeBuddyKit

/// A workflow or subagents working for the session. Read from the parent transcript
/// only: counting the agents' own files would mean watching them.
struct RowDelegationBadge: View {
    let session: AgentSession
    let l10n: Strings

    var body: some View {
        if let text {
            VibeBadge(text: text, monospaced: true)
                .help(l10n.delegationHint)
        }
    }

    /// A workflow names itself; its agents are its business.
    private var text: String? {
        guard session.isLive else { return nil }
        if session.workflowsRunning > 0 { return l10n.workflowsBadge(session.workflowsRunning) }
        if session.subagentsRunning > 0 { return l10n.agentsBadge(session.subagentsRunning) }
        return nil
    }
}
