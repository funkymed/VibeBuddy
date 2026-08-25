import SwiftUI

/// Every button the panel draws, in one place.
struct VibeButton: View {
    /// What the button means, which decides what it looks like.
    enum Role {
        /// Stops Claude.
        case deny
        /// VibeBuddy's own blue: every action that goes forward.
        case accent
        /// Everything else: « Toujours autoriser », « Annuler ».
        case neutral
    }

    let title: String
    var role: Role = .neutral
    /// Fills the width and shows a chevron — a row to pick, not a chip to press.
    var isRow = false
    /// The one the eye should land on first.
    var isProminent = false
    /// Told when the pointer enters or leaves, so a list can move the accent from one of
    /// its rows to another.
    var onHover: (Bool) -> Void = { _ in }
    var action: () -> Void

    @State private var hovering = false

    private var wearsAccent: Bool {
        isProminent || (isRow && hovering && role == .neutral)
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, isRow ? VibeTheme.Spacing.m : VibeTheme.Spacing.l)
                // Height, not padding: both numbers come off the reference, and a
                // padding would re-derive them from whatever the font happens to
                // measure.
                .frame(height: isRow ? VibeTheme.Control.row : VibeTheme.Control.decision)
                .frame(maxWidth: isRow ? .infinity : nil, alignment: .leading)
                // One shared implementation for the halo; see `neonHalo`.
                .neonHalo(shape, isOn: wearsAccent || role == .accent || (role == .deny && hovering),
                          colour: role == .deny ? VibeTheme.Glow.deny : VibeTheme.Glow.outer)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(stroke, lineWidth: VibeTheme.Border.width))
                // Light pooling just inside the edge, as a stroke rather than a blur: a
                // second blurred layer is what cost this repository 15 Mo and five
                // wakeups a second the last time.
                .overlay(
                    shape
                        .inset(by: 1.5)
                        .strokeBorder(wearsAccent || role == .accent
                                      ? VibeTheme.Glow.inner : .clear,
                                      lineWidth: 1))
        }
        .contentShape(shape)
        .buttonStyle(.plain)
        // Both, and the order matters.
        .contentShape(shape)
        .pointingHandCursor {
            hovering = $0
            onHover($0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isRow {
            HStack(spacing: VibeTheme.Spacing.s) {
                // The prominent row says so in its own label, not only in its border: a
                // blue frame around white text asks « which one is this », a blue word
                // answers it.
                Text(title)
                    .font(VibeTheme.Typography.body)
                    .foregroundStyle(wearsAccent ? VibeTheme.Accent.primary : PanelInk.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: VibeTheme.Spacing.s)
                // Says the row goes somewhere.
                Image(systemName: wearsAccent ? "arrow.right" : "chevron.right")
                    .font(.system(size: wearsAccent ? 12 : 11, weight: .semibold))
                    .foregroundStyle(wearsAccent ? VibeTheme.Accent.cyan : PanelInk.tertiary)
            }
        } else {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }

    /// One radius for everything, and it is not a capsule.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
    }

    private var tint: Color {
        switch role {
        case .deny: return PermissionInk.removed
        case .accent: return VibeTheme.Accent.primary
        case .neutral: return PanelInk.secondary
        }
    }

    /// Each button sits in its own colour, faintly. Measured off the reference,
    /// solving each interior against the panel behind it: a refusal is red at about 7 %,
    /// an accented control blue at about 3 %, a neutral row white at 2,5 %. None of them
    /// is a grey plate — which is what a single neutral fill at 10 % had turned all
    /// three into.
    private var fill: Color {
        if wearsAccent || role == .accent {
            return hovering ? VibeTheme.Accent.washHover : VibeTheme.Accent.wash
        }
        if role == .deny {
            return PermissionInk.removed.opacity(hovering ? 0.12 : 0.07)
        }
        return hovering ? VibeTheme.Surface.interactiveHover : VibeTheme.Surface.interactive
    }

    private var stroke: Color {
        if wearsAccent || role == .accent {
            return hovering ? VibeTheme.Accent.borderHover : VibeTheme.Accent.border
        }
        if role == .deny {
            // Barely tinted, and only under the pointer does it show at all.
            return PermissionInk.removed.opacity(hovering ? 0.40 : 0.18)
        }
        return hovering ? VibeTheme.Border.strong : VibeTheme.Border.subtle
    }
}
