import SwiftUI
import NotchBuddyKit

/// Top row of the expanded panel: who we are, what is happening, how to quit.
///
/// The buddy repeats here rather than disappearing when the panel opens. It is
/// the app's identity, and losing it on expand would make the panel feel like a
/// different window rather than the same object unfolded.
struct PanelHeader: View {
    let buddy: BuddyManifest?
    let expression: BuddyExpression
    let sessions: [AgentSession]
    @Bindable var budget: AnimationBudget
    let l10n: Strings
    var onSettings: () -> Void
    var onQuit: () -> Void

    private var live: [AgentSession] { sessions.filter(\.isLive) }

    /// One line saying what the agents are collectively doing.
    ///
    /// Aggregated rather than listed: the detail is two rows below, and a header
    /// that enumerates is a header nobody reads.
    private var summary: String {
        if live.isEmpty { return l10n.noSessions }
        let working = live.filter { $0.action != .none }.count
        let waiting = live.filter(\.turnEnded).count
        var parts: [String] = []
        if working > 0 { parts.append(l10n.sessionsWorking(working)) }
        if waiting > 0 { parts.append(l10n.sessionsWaiting(waiting)) }
        return parts.isEmpty ? l10n.sessionsIdle(live.count) : parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let buddy {
                BuddyView(manifest: buddy, expression: expression, budget: budget)
                    .fixedSize()
            }

            // Just what the agents are doing. The app's own name sits on the
            // identity line below, where it is read once rather than competing
            // with the state on every glance.
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            Spacer(minLength: 8)

            counterChip
            settingsButton
            quitButton
        }
    }

    /// Live over total, so a session that ended is still visible as history
    /// without being counted as running.
    private var counterChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(live.isEmpty ? Color.white.opacity(0.3) : .green)
                .frame(width: 7, height: 7)
            Text("\(live.count) / \(sessions.count)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    /// The only way in to the settings window.
    ///
    /// The app is an accessory with no menu bar, so `⌘,` reaches nothing. This
    /// gear is the entire entry point.
    private var settingsButton: some View {
        Button(action: onSettings) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n.settings)
    }

    /// The only way out.
    ///
    /// The app has no Dock icon and no menu bar, so without this there is no
    /// way to quit it short of `pkill` — which is how the reference
    /// implementation ended up putting one here too.
    private var quitButton: some View {
        Button(action: onQuit) {
            Image(systemName: "power")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n.quit)
    }
}

enum AppVersion {
    static var short: String {
        let info = Bundle.main.infoDictionary
        return "v" + ((info?["CFBundleShortVersionString"] as? String) ?? "0.1.0")
    }
}
