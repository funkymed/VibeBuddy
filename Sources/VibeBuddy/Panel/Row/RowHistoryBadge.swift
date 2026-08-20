import SwiftUI
import VibeBuddyKit

/// How many runs this directory has accumulated, live ones marked.
struct RowHistoryBadge: View {
    let group: SessionGroup
    let l10n: Strings

    var body: some View {
        Text(group.liveCount > 1 ? "×\(group.liveCount)/\(group.count)" : "×\(group.count)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(PanelInk.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(PanelInk.stroke))
            .help(l10n.sessionHistory(group.count))
    }
}
