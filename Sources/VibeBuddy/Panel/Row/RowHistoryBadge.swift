import SwiftUI
import VibeBuddyKit

/// How many runs this directory has accumulated, live ones marked.
struct RowHistoryBadge: View {
    let group: SessionGroup
    let l10n: Strings

    var body: some View {
        VibeBadge(
            text: group.liveCount > 1 ? "×\(group.liveCount)/\(group.count)" : "×\(group.count)",
            monospaced: true)
            .help(l10n.sessionHistory(group.count))
    }
}
