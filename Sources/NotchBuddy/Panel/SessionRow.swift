import SwiftUI
import NotchBuddyKit

/// One agent session.
///
/// `Equatable` on purpose: the panel re-renders on every session snapshot, and
/// without this every row rebuilds even when only one of them changed. The
/// reference implementation's row is inlined in a 3 738-line view, which is why
/// its whole panel invalidates on any update.
struct SessionRow: View, Equatable {
    let group: SessionGroup
    let l10n: Strings
    /// Called with the pid to jump to. Absent for a row with nothing to jump
    /// to, which is what makes a dead session read as dead rather than as
    /// broken: no pointer, no highlight, no click.
    var onJump: ((pid_t) -> Void)?

    @State private var hovering = false

    /// Only a live session has a process to go back to. A finished one is
    /// history, and its terminal has moved on.
    private var jumpPID: pid_t? { session.isLive ? session.pid : nil }

    private var session: AgentSession { group.primary }

    // nonisolated: a View is MainActor-isolated, and an Equatable conformance
    // that crosses that boundary is a data race under Swift 6. The comparison
    // touches only the value, so it needs no isolation.
    nonisolated static func == (a: SessionRow, b: SessionRow) -> Bool {
        a.group == b.group
    }

    var body: some View {
        HStack(spacing: 10) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(session.isLive ? 1 : 0.45))
                        .lineLimit(1)
                    if !session.effort.isEmpty { effortBadge }
                    // After the effort, on the title line: it belongs with the
                    // other badges rather than in the grey run below, where a
                    // coloured capsule sat lower than the name it qualifies.
                    stateChip
                    // Only when there is history to hint at. A `×1` on every
                    // row would be noise standing in for information.
                    if group.hasHistory { historyBadge }
                }
                HStack(spacing: 6) {
                    if !session.model.isEmpty {
                        Text(shortModel)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                // The full path, truncated from the head: the tail is what
                // distinguishes two projects, the leading `/Users/name/Sites`
                // is the same for all of them.
                Text(session.cwd)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.32))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            contextGauge
            Text(relativeActivity)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            if !session.permissionMode.isEmpty { modeBadge }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(.white.opacity(hovering && jumpPID != nil ? 0.10 : 0.05)))
        // The whole row, not a button inside it: the target is the line the eye
        // already treats as one object, and a small affordance in a 20 pt row
        // would be a smaller target than the row it sits in.
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { hovering = $0 }
        .onTapGesture { if let pid = jumpPID { onJump?(pid) } }
        .help(jumpPID != nil ? l10n.jumpHint : "")
    }

    /// Colour carries the state before the text does.
    private var statusDot: some View {
        Circle()
            .fill(dotColour)
            .frame(width: 9, height: 9)
    }

    private var dotColour: Color {
        guard session.isLive else { return .white.opacity(0.2) }
        // A question outranks everything, including an error underneath it: the
        // agent is stopped, and that is the only state where nothing moves
        // until the user acts.
        if session.awaitingAnswer { return .blue }
        if session.lastResultWasError { return .red }
        if session.action != .none { return .green }
        if session.turnEnded { return .orange }
        return .white.opacity(0.35)
    }

    /// The coarse state, as a word in its own colour.
    ///
    /// A chip rather than another run of grey text: the state is the one thing
    /// on the row that decides whether to act, and it has to be findable
    /// without reading. The dot on the left carries the same colour for the
    /// scan across rows; the chip carries the word for the row you stopped on.
    private var stateChip: some View {
        Text(stateLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(dotColour)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(dotColour.opacity(0.16)))
            .fixedSize()
            .help(session.awaitingAnswer ? (session.question ?? l10n.alertWaiting) : stateLabel)
    }

    /// One vocabulary, in the same order as `dotColour` — the word and the
    /// colour must never disagree, so they read the same facts in the same
    /// order.
    private var stateLabel: String {
        guard session.isLive else { return l10n.stateEnded }
        if session.awaitingAnswer { return l10n.stateAwaiting }
        if session.lastResultWasError { return l10n.stateFailed }
        if session.action != .none { return l10n.stateWorking }
        if session.turnEnded { return l10n.stateFinished }
        return l10n.stateIdle
    }

    /// Model, uptime, and what the agent is pointed at — the subject is what
    /// turns "édition" into "édition de NotchPanel.swift".
    /// What follows the chip: the tool in flight, then how long the session has
    /// been up.
    ///
    /// The chip already carries the coarse state, so this is only the detail —
    /// "python3 - <<'PY'" is what distinguishes two sessions that are both
    /// "en cours". A pending question replaces it entirely: a row reading
    /// "planification · ExitPlanMode · <question>" buries the part that needs
    /// an answer.
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

    /// Context used: a ring *and* the number.
    ///
    /// The ring alone was ambiguous — it reads "roughly half" but the window is
    /// either 200k or 1M, and which one changes what half means.
    private var contextGauge: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: session.contextFraction)
                    .stroke(gaugeColour, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 17, height: 17)
            Text("\(Int((session.contextFraction * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(gaugeColour.opacity(0.9))
        }
        .help(l10n.contextTooltip(session.contextTokens, session.contextWindow))
    }

    private var gaugeColour: Color {
        switch session.contextFraction {
        case ..<0.7: return .white.opacity(0.45)
        case ..<0.9: return .orange
        default:     return .red
        }
    }

    /// Reasoning effort. Coloured only when it is unusually high, so the
    /// common case does not shout.
    private var effortBadge: some View {
        Text(session.effort)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(session.effort == "high" ? .purple.opacity(0.95) : .white.opacity(0.5))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(
                session.effort == "high" ? .purple.opacity(0.18) : .white.opacity(0.07)))
    }

    /// How many runs this directory has accumulated, live ones marked.
    private var historyBadge: some View {
        Text(group.liveCount > 1 ? "×\(group.liveCount)/\(group.count)" : "×\(group.count)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.07)))
            .help(l10n.sessionHistory(group.count))
    }

    private var modeBadge: some View {
        Text(session.permissionMode)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.09)))
    }

    private var relativeActivity: String {
        Self.duration(since: session.lastActivity)
    }

    /// Compact durations: `3s`, `12m`, `8h41`.
    ///
    /// Written here rather than with a `RelativeDateTimeFormatter` because that
    /// produces "il y a 8 heures", which is three times wider than the column
    /// and less precise.
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
