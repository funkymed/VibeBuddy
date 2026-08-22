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
    /// How many requests are queued behind this one.
    var waiting: Int = 0
    /// True only for the offscreen host in `NotchPanel` that asks this view how
    /// tall it wants to be. See the note on the body.
    var measuring = false
    let l10n: Strings
    var onDeny: () -> Void
    var onAllow: () -> Void
    var onAlwaysAllow: () -> Void
    /// `AskUserQuestion`'s only way back. The hook can allow or deny and nothing
    /// else, so T6 sends the chosen option as a `deny` message phrased as the
    /// answer — the model reads it as a tool result and carries on. Defaulted so
    /// the three tools that never ask a question need not pass it.
    var onAnswer: (String) -> Void = { _ in }

    // The header of the deployed panel — buddy, counter, settings, quit — is
    // `DeployedPanel`'s and is drawn above this. What follows is what makes
    // *this* state different from the sessions one.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerText

            // **Wide, not tall — and scrolling when it has to be.**
            //
            // Two states, and both are needed. Being *measured*, it must answer
            // its natural height, so the window can be exactly as tall as what
            // it shows; a scroller would answer « as tall as you like » and
            // every request would come out the same size again.
            //
            // Being *drawn*, the window's height is already decided and may be
            // at the 460 pt ceiling, so the summary must give way rather than
            // overflow. It used not to: a long question pushed the panel past
            // the ceiling and the contents spilled out **both ends** — the
            // buddy cut off at the top, the decision bar cut off at the bottom,
            // nothing scrollable anywhere. The header and the bar are the two
            // things that must never move; what is between them is what gives.
            if measuring {
                summary
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical) {
                    summary
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
                .frame(maxHeight: .infinity)
            }

            decisionBar
        }
    }

    // MARK: - What is being asked

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // In the accent, and it is the only section label that gets
                // it: a permission on screen is the one thing the panel ever
                // shows that is *waiting on the user*. Section 11 of the brief.
                Text(l10n.permissionTitle)
                    .font(VibeTheme.Typography.section)
                    .foregroundStyle(VibeTheme.Accent.primary)
                    .tracking(VibeTheme.Typography.sectionTracking)
                Spacer(minLength: 8)
                if waiting > 0 { waitingChip }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.toolName)
                    .font(VibeTheme.Typography.title)
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
        HStack(spacing: VibeTheme.Spacing.s) {
            VibeButton(title: l10n.permissionDeny, role: .deny, action: onDeny)

            Spacer(minLength: VibeTheme.Spacing.m)

            // **Never on a question.** Read in Claude Code 2.1.239: a tool that
            // declares `requiresUserInteraction` — `AskUserQuestion` does,
            // unconditionally — has any `allow` from a hook discarded
            // (`if(!updatedInput && requiresUserInteraction()) return null`),
            // and the binary carries a `suppress_always_allow_rule` flag for
            // the same reason. A rule written here would therefore do nothing
            // in Claude Code and everything here: our own always-allow short
            // circuit would answer every later question without showing it, so
            // the panel would stop offering questions **for good**, silently,
            // because of a line in the user's own settings file.
            if !isQuestion {
                VibeButton(title: l10n.permissionAlwaysAllow, role: .neutral,
                           action: onAlwaysAllow)
                    // Says out loud that this one writes to the user's own
                    // settings file — the consent half of R1.
                    .help(l10n.permissionAlwaysAllowHint)
            }

            // The action that goes forward, whichever it is: on a question it
            // hands the ask back to Claude Code's own picker, on anything else
            // it lets the tool run. One accent for both — the label says which,
            // the colour says only « this is the way on ».
            VibeButton(
                title: isQuestion ? l10n.permissionAnswerInTerminal : l10n.permissionAllow,
                role: .accent, action: onAllow)
        }
    }

    /// Whether the request is the agent waiting on a person rather than asking
    /// for something to be run.
    private var isQuestion: Bool {
        if case .question = model.summary { return true }
        return false
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
