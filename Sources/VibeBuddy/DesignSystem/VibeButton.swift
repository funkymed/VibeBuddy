import SwiftUI

/// Every button the panel draws, in one place.
///
/// There were four implementations of « a label you can click » — the decision
/// bar, the question options, the consent screen, the header's icons — and they
/// had already drifted: two radii, three paddings, two ways of saying « this one
/// matters ». A fifth would have been the one nobody noticed.
///
/// **Hover swaps a fill; it is not animated.** RFC-007 §2 forbids anything that
/// keeps drawing while the user thinks, and a permission panel is exactly the
/// place where nothing happens for a long time. The change is instant, which on
/// a pointer that has just moved reads as responsive rather than abrupt.
struct VibeButton: View {

    /// What the button means, which decides what it looks like.
    enum Role {
        /// Stops Claude. The only decision that keeps a colour of its own —
        /// and it keeps it in the label, not in a fill: a red wash behind a red
        /// word on black is what made the first attempt ugly.
        case deny
        /// VibeBuddy's own blue: **every** action that goes forward. Allowing a
        /// tool, answering in the terminal, writing the rule.
        ///
        /// It used to be green, matching `PermissionInk.added`. That was a
        /// mistake of transfer: green and red mean *added* and *removed* inside
        /// a diff, where they label two halves of one text. On a pair of
        /// buttons they read as a traffic light, and a traffic light is the
        /// loudest thing on a panel whose job is to be quiet.
        case accent
        /// Everything else: « Toujours autoriser », « Annuler ».
        case neutral
    }

    let title: String
    var role: Role = .neutral
    /// Fills the width and shows a chevron — a row to pick, not a chip to press.
    var isRow = false
    /// The one the eye should land on first. At most one per screen.
    var isProminent = false
    /// Told when the pointer enters or leaves, so a list can move the accent
    /// from one of its rows to another.
    var onHover: (Bool) -> Void = { _ in }
    var action: () -> Void

    @State private var hovering = false

    /// Whether this button wears the accent.
    ///
    /// **One source, and it is this button's own pointer state.** It went
    /// through the list for a while, because a row was accented by default and
    /// two of them could light at once. That default is gone — nothing is
    /// selected until the pointer says so — and with it the reason to split the
    /// decision in two.
    ///
    /// Splitting it was what broke fast movement: the fill was drawn from the
    /// local `hovering`, the accent from the list's index, and SwiftUI delivers
    /// enter and exit in whichever order it likes. Sweeping across a list left
    /// one button filled and another accented. A mouse is only ever in one
    /// place; asking the button itself cannot contradict that.
    private var wearsAccent: Bool {
        isProminent || (isRow && hovering && role == .neutral)
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, isRow ? VibeTheme.Spacing.m : VibeTheme.Spacing.l)
                // Height, not padding: both numbers come off the reference,
                // and a padding would re-derive them from whatever the font
                // happens to measure.
                .frame(height: isRow ? VibeTheme.Control.row : VibeTheme.Control.decision)
                .frame(maxWidth: isRow ? .infinity : nil, alignment: .leading)
                // One shared implementation for the halo; see `neonHalo`.
                .neonHalo(shape, isOn: wearsAccent || role == .accent || (role == .deny && hovering),
                          colour: role == .deny ? VibeTheme.Glow.deny : VibeTheme.Glow.outer)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(stroke, lineWidth: VibeTheme.Border.width))
                // Light pooling just inside the edge, as a stroke rather than a
                // blur: a second blurred layer is what cost this repository
                // 15 Mo and five wakeups a second the last time.
                .overlay(
                    shape
                        .inset(by: 1.5)
                        .strokeBorder(wearsAccent || role == .accent
                                      ? VibeTheme.Glow.inner : .clear,
                                      lineWidth: 1))
        }
        .contentShape(shape)
        .buttonStyle(.plain)
        // **Both**, and the order matters.
        //
        // `contentShape` after `buttonStyle` gives the *button* one hit area.
        // But `pointingHandCursor` installs its own `onHover` on top, and that
        // one tests against whatever is opaque underneath — the label's text
        // and its background, with the gaps between them left out. Hovering the
        // words worked; hovering a hair above them did not, and moving along a
        // line of text made the highlight blink.
        //
        // `contentShape` again, *before* the hover modifier, hands it a single
        // solid rectangle to test against.
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
                // The prominent row says so in its own label, not only in its
                // border: a blue frame around white text asks « which one is
                // this », a blue word answers it.
                Text(title)
                    .font(VibeTheme.Typography.body)
                    .foregroundStyle(wearsAccent ? VibeTheme.Accent.primary : PanelInk.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: VibeTheme.Spacing.s)
                // Says the row goes somewhere. Filled on the prominent one,
                // outlined on the rest — the difference is the whole hierarchy.
                // Follows the accent, not `isProminent`: the arrow is what
                // says « this is the one that would go », and that is now
                // decided by the pointer.
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

    /// **One radius for everything, and it is not a capsule.**
    ///
    /// The decisions were pills. A pill is a chip — a tag, a filter, something
    /// you toggle — and reading « Refuser » out of one makes it look optional.
    /// The reference design draws every button as the same rounded block,
    /// which is also what makes a row of them line up: two shapes in one bar
    /// never share an optical baseline.
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

    /// **Each button sits in its own colour, faintly.**
    ///
    /// Measured off the reference, solving each interior against the panel
    /// behind it: a refusal is red at about 7 %, an accented control blue at
    /// about 3 %, a neutral row white at 2,5 %. None of them is a grey plate —
    /// which is what a single neutral fill at 10 % had turned all three into.
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
