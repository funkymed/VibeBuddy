import SwiftUI
import VibeBuddyKit

/// One agent session.
///
/// Keep the `Equatable` conformance: the panel re-renders on every session
/// snapshot, and without it every row rebuilds when only one of them changed.
struct SessionRow: View, Equatable {
    let group: SessionGroup
    let l10n: Strings
    /// Nil for a row with nothing to jump to: no pointer, no highlight, no click.
    var onJump: ((pid_t) -> Void)?

    @State private var hovering = false

    private var jumpPID: pid_t? { session.isLive ? session.pid : nil }

    private var session: AgentSession { group.primary }

    // nonisolated: a View is MainActor-isolated, and an Equatable conformance
    // that crosses that boundary is a data race under Swift 6.
    nonisolated static func == (a: SessionRow, b: SessionRow) -> Bool {
        a.group == b.group
    }

    var body: some View {
        // A dead row is not a control: no button, no hover, no tooltip.
        if let pid = jumpPID {
            Button { onJump?(pid) } label: { content }
                .buttonStyle(.plain)
                .pointingHandCursor { hovering = $0 }
                .help(l10n.jumpHint)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            statusDot

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.projectName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(session.isLive ? PanelInk.primary : PanelInk.secondary)
                        .lineLimit(1)
                    if !session.effort.isEmpty { RowEffortBadge(session: session) }
                    RowStateChip(session: session, l10n: l10n)
                    if group.hasHistory { RowHistoryBadge(group: group, l10n: l10n) }
                }
                HStack(spacing: 8) {
                    if !session.model.isEmpty {
                        Text(shortModel)
                            .font(.system(size: 12))
                            .foregroundStyle(PanelInk.secondary)
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(PanelInk.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                // Truncate from the head: the tail distinguishes two projects.
                Text(session.cwd)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PanelInk.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            RowContextGauge(session: session, l10n: l10n)
            Text(relativeActivity)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(PanelInk.secondary)
            if !session.permissionMode.isEmpty { RowModeBadge(session: session) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(hovering && jumpPID != nil ? PanelInk.stroke : PanelInk.surface))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private var statusDot: some View {
        Circle()
            .fill(SessionStateStyle.colour(session))
            .frame(width: 9, height: 9)
    }

    /// What follows the chip. See RFC-008, "Notes d'implémentation".
    private var detail: String {
        var parts: [String] = []
        if session.awaitingAnswer {
            if let question = session.question { parts.append(question) }
        } else if !session.status.isEmpty {
            parts.append(session.status + (session.subject.map { " · \($0)" } ?? ""))
        }
        parts.append(l10n.since(Self.duration(since: session.startedAt)))
        return parts.joined(separator: " · ")
    }

    /// `claude-opus-5` → `opus 5`. See `ModelName` for why the version stays.
    private var shortModel: String { ModelName.short(session.model) }

    private var relativeActivity: String {
        Self.duration(since: session.lastActivity)
    }

    /// Compact durations: `3s`, `12m`, `8h41`. A `RelativeDateTimeFormatter`
    /// gives "il y a 8 heures" — three times the column width, and less precise.
    static func duration(since date: Date) -> String {
        let seconds = Int(max(0, Date().timeIntervalSince(date)))
        switch seconds {
        case ..<60:     return "\(seconds)s"
        case ..<3600:   return "\(seconds / 60)m"
        case ..<86_400:
            let h = seconds / 3600, m = (seconds % 3600) / 60
            return m > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(h)h"
        default:        return "\(seconds / 86_400)j"
        }
    }
}
