import SwiftUI
import VibeBuddyKit

/// Top row of the expanded panel: buddy, aggregate state, settings, quit.
struct PanelHeader: View {
    let buddy: BuddyManifest?
    let expression: BuddyExpression
    /// The size the buddy is drawn at in the collapsed pill.
    var buddyBox: CGSize = .zero
    let sessions: [AgentSession]
    @Bindable var budget: AnimationBudget
    let l10n: Strings
    var onSettings: () -> Void
    var onQuit: () -> Void

    private var live: [AgentSession] { sessions.filter(\.isLive) }

    private var working: Int { live.filter { SessionDisplayState.of($0) == .working }.count }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // The buddy's seat.
            if buddy != nil {
                Color.clear.frame(width: buddyBox.width, height: buddyBox.height)
            }

            if live.isEmpty {
                Text(l10n.noSessions)
                    .font(.system(size: 13))
                    .foregroundStyle(PanelInk.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            counterChip
            settingsButton
            quitButton
        }
    }

    /// Working over live, not live over total.
    private var counterChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(SessionStateStyle.colour(SessionDisplayState.aggregate(of: sessions) ?? .ended))
                .frame(width: 7, height: 7)
            Text("\(working) / \(live.count)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelInk.primary)
                .contentTransition(.numericText())
                .help(l10n.stateWorking)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(PanelInk.stroke))
    }

    /// The app is an accessory with no menu bar, so `⌘,` reaches nothing: this gear is
    /// the entire entry point.
    private var settingsButton: some View {
        Button(l10n.settings, systemImage: "slider.horizontal.3", action: onSettings)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(PanelInk.secondary)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .help(l10n.settings)
            .pointingHandCursor()
    }

    /// No Dock icon and no menu bar: without this there is no way to quit short of
    /// `pkill`.
    private var quitButton: some View {
        Button(l10n.quit, systemImage: "power", action: onQuit)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(PanelInk.secondary)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .help(l10n.quit)
            .pointingHandCursor()
    }
}
