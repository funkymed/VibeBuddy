import SwiftUI
import VibeBuddyKit

/// The permission panel: what is being asked, and the three ways to answer it. The
/// reference pulsed a text at 20 Hz through `TimelineView(.periodic(by: 0.05))`
/// (`NotchContentView.swift:773`) for the entire time the user was thinking — the most
/// expensive moment to spend wakeups on is the one where nothing happens.
struct PermissionPanelView: View {
    let model: PermissionRequestModel
    /// How many requests are queued behind this one.
    var waiting: Int = 0
    /// True only for the offscreen host in `NotchPanel` that asks this view how tall it
    /// wants to be.
    var measuring = false
    let l10n: Strings
    var onDeny: () -> Void
    var onAllow: () -> Void
    var onAlwaysAllow: () -> Void
    /// `AskUserQuestion`'s only way back.
    var onAnswer: (String) -> Void = { _ in }

    // The header of the deployed panel — buddy, counter, settings, quit — is
    // `DeployedPanel`'s and is drawn above this.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerText

            // Wide, not tall — and scrolling when it has to be. Being *drawn*, the
            // window's height is already decided and may be at the 460 pt ceiling, so
            // the summary must give way rather than overflow.
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

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // In the accent, and it is the only section label that gets it: a
                // permission on screen is the one thing the panel ever shows that is
                // *waiting on the user*.
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

    /// Routes on the kind of ask, not on the tool's name: `Edit` and `Write` differ by a
    /// tool label, not by what the user has to look at.
    @ViewBuilder
    private var summary: some View {
        switch model.summary {
        case let .shell(command, description):
            ShellSummaryView(command: command, description: description, l10n: l10n)

        case let .diff(path, before, after):
            DiffSummaryView(path: path, before: before, after: after, l10n: l10n)

        // A file being created has no left side: it is a diff whose `before` is empty,
        // and the diff view already draws that as all-green.
        case let .write(path, contents):
            DiffSummaryView(path: path, before: "", after: contents, l10n: l10n)

        case let .read(path):
            URLSummaryView(target: path, l10n: l10n)

        case let .url(target):
            URLSummaryView(target: target, l10n: l10n)

        case let .question(prompt, options):
            AskQuestionView(prompt: prompt, options: options, l10n: l10n, onAnswer: onAnswer)

        // An unknown tool's fields, one per line, in the same monospace block a command
        // gets.
        case let .other(fields):
            ShellSummaryView(
                command: fields.map { "\($0.name): \($0.value)" }.joined(separator: "\n"),
                description: nil, l10n: l10n)
        }
    }

    /// Deny sits apart from the two that say yes, so the destructive answer and the
    /// permanent one are never neighbours under a fast cursor.
    private var decisionBar: some View {
        HStack(spacing: VibeTheme.Spacing.s) {
            VibeButton(title: l10n.permissionDeny, role: .deny, action: onDeny)

            Spacer(minLength: VibeTheme.Spacing.m)

            // Never on a question. Read in Claude Code 2.1.239: a tool that
            // declares `requiresUserInteraction` — `AskUserQuestion` does,
            // unconditionally — has any `allow` from a hook discarded
            // (`if(!updatedInput && requiresUserInteraction()) return null`), and the
            // binary carries a `suppress_always_allow_rule` flag for the same reason.
            if !isQuestion {
                VibeButton(title: l10n.permissionAlwaysAllow, role: .neutral,
                           action: onAlwaysAllow)
                    // Says out loud that this one writes to the user's own settings
                    // file — the consent half of R1.
                    .help(l10n.permissionAlwaysAllowHint)
            }

            // The action that goes forward, whichever it is: on a question it hands the
            // ask back to Claude Code's own picker, on anything else it lets the tool
            // run.
            VibeButton(
                title: isQuestion ? l10n.permissionAnswerInTerminal : l10n.permissionAllow,
                role: .accent, action: onAllow)
        }
    }

    /// Whether the request is the agent waiting on a person rather than asking for
    /// something to be run.
    private var isQuestion: Bool {
        if case .question = model.summary { return true }
        return false
    }
}
