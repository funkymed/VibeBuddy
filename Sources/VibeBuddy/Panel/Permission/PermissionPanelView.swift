import SwiftUI
import VibeBuddyKit

/// The permission panel: what is being asked, and the three ways to answer it.
///
/// **Static by construction.** RFC-007 forbids any permanent animation here. The
/// reference pulsed a text at 20 Hz through `TimelineView(.periodic(by: 0.05))`
/// (`NotchContentView.swift:773`) for the entire time the user was thinking —
/// the most expensive moment to spend wakeups on is the one where nothing
/// happens. This panel appears, waits, and goes away: no timer, no timeline, no
/// repeating animation.
///
/// One request on screen at a time; the rest are a number. Arbitrage of
/// 2026-08-21, answers Q2.
struct PermissionPanelView: View {
    let model: PermissionRequestModel
    /// The buddy's seat. `NotchShellView` draws one buddy across both states,
    /// as an overlay pinned to the panel's top-leading corner — the same corner
    /// this header starts in. Without the seat reserved, the face is drawn on
    /// top of the tool's name. `PanelHeader` reserves it the same way.
    var buddyBox: CGSize = .zero
    /// How many requests are queued behind this one.
    var waiting: Int = 0
    let l10n: Strings
    var onDeny: () -> Void
    var onAllow: () -> Void
    var onAlwaysAllow: () -> Void
    /// `AskUserQuestion`'s only way back. The hook can allow or deny and nothing
    /// else, so T6 sends the chosen option as a `deny` message phrased as the
    /// answer — the model reads it as a tool result and carries on. Defaulted so
    /// the three tools that never ask a question need not pass it.
    var onAnswer: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            summary
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            decisionBar
        }
        .padding(.horizontal, PanelMetrics.contentInset.width)
        .padding(.top, PanelMetrics.contentInset.height)
        .padding(.bottom, 12)
    }

    // MARK: - Header

    private var header: some View {
        // The seat runs beside the **whole** header, not one of its rows: the
        // buddy is 30 pt tall and the header is two lines, so reserving on the
        // second line alone still put the face over the first.
        HStack(alignment: .top, spacing: 12) {
            if buddyBox.width > 0 {
                Color.clear.frame(width: buddyBox.width, height: buddyBox.height)
            }
            headerText
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(l10n.permissionTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PanelInk.secondary)
                    .tracking(0.8)
                Spacer(minLength: 8)
                if waiting > 0 { waitingChip }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.toolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PanelInk.primary)
                    .lineLimit(1)
                if let project {
                    Text(project)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(PanelInk.tertiary)
                        .lineLimit(1)
                        // The tail is what tells two projects apart.
                        .truncationMode(.head)
                }
                Spacer(minLength: 8)
            }
        }
    }

    private var waitingChip: some View {
        Text(l10n.permissionWaiting(waiting))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(PanelInk.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(PanelInk.stroke))
            .fixedSize()
    }

    private var project: String? {
        guard let cwd = model.cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    // MARK: - Summary

    /// Routes on the kind of ask, not on the tool's name: `Edit` and `Write`
    /// differ by a tool label, not by what the user has to look at.
    @ViewBuilder
    private var summary: some View {
        switch model.summary {
        case let .shell(command, description):
            ShellSummaryView(command: command, description: description, l10n: l10n)

        case let .diff(path, before, after):
            DiffSummaryView(path: path, before: before, after: after, l10n: l10n)

        // A file being created has no left side: it is a diff whose `before` is
        // empty, and the diff view already draws that as all-green.
        case let .write(path, contents):
            DiffSummaryView(path: path, before: "", after: contents, l10n: l10n)

        case let .read(path):
            URLSummaryView(target: path, l10n: l10n)

        case let .url(target):
            URLSummaryView(target: target, l10n: l10n)

        case let .question(prompt, options):
            AskQuestionView(prompt: prompt, options: options, l10n: l10n, onAnswer: onAnswer)

        // An unknown tool's fields, one per line, in the same monospace block a
        // command gets. Showing them at all is the point (R6); styling them is
        // not.
        case let .other(fields):
            ShellSummaryView(
                command: fields.map { "\($0.name): \($0.value)" }.joined(separator: "\n"),
                description: nil, l10n: l10n)
        }
    }

    // MARK: - Decisions

    /// Deny sits apart from the two that say yes, so the destructive answer and
    /// the permanent one are never neighbours under a fast cursor.
    ///
    /// The two tints are the diff's own red and green, from `PermissionInk`:
    /// refusing and removing mean the same thing to the eye, and the panel must
    /// not teach two reds.
    private var decisionBar: some View {
        HStack(spacing: 8) {
            decision(l10n.permissionDeny, tint: PermissionInk.removed, action: onDeny)

            Spacer(minLength: 12)

            decision(l10n.permissionAlwaysAllow, tint: PanelInk.secondary,
                     action: onAlwaysAllow)
                // Says out loud that this one writes to the user's own settings
                // file — the consent half of R1.
                .help(l10n.permissionAlwaysAllowHint)

            decision(l10n.permissionAllow, tint: PermissionInk.added, action: onAllow)
        }
    }

    private func decision(_ title: String, tint: Color,
                          action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(PanelInk.surface))
            .overlay(Capsule().stroke(PanelInk.stroke))
            .contentShape(Capsule())
            .pointingHandCursor()
    }
}
