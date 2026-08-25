import SwiftUI
import VibeBuddyKit

/// One session's recent history, read from its transcript.
struct SessionDetailView: View {
    let session: AgentSession
    let l10n: Strings
    let loader: SessionTimelineLoader
    var onBack: () -> Void

    /// Nil while the read is in flight; the empty array is a session with nothing in it,
    /// which the transcript being unreadable is not.
    @State private var events: [TimelineEvent]?
    @State private var unreadable = false

    var body: some View {
        VStack(alignment: .leading, spacing: VibeTheme.Spacing.m) {
            header
            VibeDivider()
            body(for: events)
        }
        // Keyed on the transcript's identity, so selecting another session while this
        // one is still loading cannot land the first read into the second view.
        .task(id: session.transcriptPath) { await load() }
    }

    private var header: some View {
        HStack(spacing: VibeTheme.Spacing.s) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(l10n.timelineBack)
                        .font(VibeTheme.Typography.secondary)
                }
                .foregroundStyle(VibeTheme.Accent.primary)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .pointingHandCursor { _ in }

            Text(l10n.timelineTitle)
                .font(VibeTheme.Typography.section)
                .foregroundStyle(VibeTheme.Accent.primary)
                .tracking(VibeTheme.Typography.sectionTracking)

            Spacer(minLength: VibeTheme.Spacing.s)

            Text(session.projectName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PanelInk.primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func body(for events: [TimelineEvent]?) -> some View {
        if unreadable {
            note(l10n.timelineUnreadable)
        } else if let events {
            if events.isEmpty {
                note(l10n.timelineEmpty)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        // Newest first: the panel opens on what just happened.
                        ForEach(events.reversed()) { event in
                            TimelineRow(event: event, l10n: l10n)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
            }
        } else {
            // No spinner: the read is a tail plus a parse, and a spinner that shows for
            // five milliseconds is a flash, not information.
            Color.clear.frame(height: 1)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(PanelInk.tertiary)
            .padding(.vertical, 12)
    }

    private func load() async {
        guard !session.transcriptPath.isEmpty else {
            unreadable = true
            return
        }
        let read = await loader.events(at: session.transcriptPath)
        unreadable = read == nil
        events = read ?? []
    }
}

/// One event.
struct TimelineRow: View {
    let event: TimelineEvent
    let l10n: Strings

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: VibeTheme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14, alignment: .center)

            Text(title)
                .font(VibeTheme.Typography.secondary)
                .foregroundStyle(tint)
                .lineLimit(1)
                .layoutPriority(1)

            if !event.text.isEmpty {
                Text(event.text)
                    .font(.system(size: 11))
                    .foregroundStyle(PanelInk.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: VibeTheme.Spacing.s)

            if let at = event.at {
                Text(SessionRow.duration(since: at))
                    .font(VibeTheme.Typography.mono(11))
                    .foregroundStyle(PanelInk.tertiary)
            }
        }
    }

    private var title: String {
        switch event.kind {
        case .prompt: l10n.timelinePrompt
        case .tool(let label): l10n.label(for: label)
        case .result(let failed): failed ? l10n.timelineResultFailed : l10n.timelineResult
        case .turnEnd(let ms): l10n.timelineTurnEnd(Self.seconds(ms))
        case .subagentStarted: l10n.timelineSubagentStarted
        case .subagentFinished: l10n.timelineSubagentFinished
        }
    }

    private var symbol: String {
        switch event.kind {
        case .prompt: "text.bubble"
        case .tool: "wrench.and.screwdriver"
        case .result(let failed): failed ? "xmark.circle" : "checkmark.circle"
        case .turnEnd: "flag.checkered"
        case .subagentStarted, .subagentFinished: "point.3.connected.trianglepath.dotted"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .result(true): SessionStateStyle.colour(.failed)
        case .prompt: PanelInk.primary
        default: PanelInk.secondary
        }
    }

    /// `12345` → `12,3 s`. Empty when the entry carried no duration, which the format
    /// string absorbs rather than showing a bare separator.
    static func seconds(_ milliseconds: Int?) -> String {
        guard let milliseconds, milliseconds > 0 else { return "" }
        return String(format: "%.1f s", Double(milliseconds) / 1000)
    }
}
