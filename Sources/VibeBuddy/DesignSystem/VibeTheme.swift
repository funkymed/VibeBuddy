import SwiftUI

/// The panel's design tokens: surfaces, accent, radii, spacing, borders.
///
/// **One table per fact.** `PanelInk` already owned the scale of whites and
/// keeps it — six levels that replaced twenty-two scattered opacity values.
/// `SessionStateStyle` already owned the state colours and keeps them. This adds
/// what neither had: the depth scale, the interactive accent, and the numbers
/// that were written inline in every view.
///
/// **Two things are deliberately absent.**
///
/// *A background token.* The panel is drawn inside the physical hole of the
/// display. Black there is not a colour, it is the absence of screen, and it is
/// what makes the window disappear into the notch — `#050608` would show as a
/// grey rectangle against the cutout's edge.
///
/// *A glow scale.* Not because glow is unwanted, but because this repository has
/// paid for unmeasured light three times: three stacked shadows on the face cost
/// 38 Mo and 5,4 wakeups/s where one costs 23 Mo and 0,2; three gradients inside
/// a phase-dependent body cost 127 Mo; `ImageRenderer` for a dozen glyphs cost
/// 101 Mo against a 40 Mo budget. Light gets its tokens once `make perf` has
/// said what one costs — on one element, not on every card at once.
enum VibeTheme {

    /// Depth, by how far a surface is lifted off the black.
    ///
    /// Each step is small on purpose: the goal is depth, not a stack of visible
    /// rectangles. These are whites over the notch's black, not opaque greys, so
    /// they compose with whatever is behind an unfilled corner.
    enum Surface {
        /// A block the content is poured into — a command, a diff, a session
        /// card, the identity.
        ///
        /// **Three percent, and the number is measured, not chosen.** Sampled
        /// out of the reference design: a card's empty area is `#080C13` where
        /// the panel around it is `#02060B` — six levels of separation, and
        /// bluish rather than grey. At 5 % white this rendered `(13,13,13)`:
        /// too light, and neutral, so the cards read as grey rectangles laid on
        /// a blue panel instead of the same material lifted slightly.
        ///
        /// Over the deployed panel's own tint this composites to about
        /// `(8,13,20)` — the reference to within a level or two.
        static let sunken = Color.white.opacity(0.03)
        /// Something you can click that is not asking to be clicked.
        ///
        /// **Two and a half percent, measured.** A neutral answer row on the
        /// reference is `(8,13,21)` over a `(2,7,14)` panel — six levels, which
        /// solves to about 2,5 % of white. It went to 10 % on the reasoning that
        /// « Refuser » looked unfilled; the real answer was that its fill should
        /// be *its own colour* rather than a grey, which is what `VibeButton`
        /// now does. A grey at 10 % is four times the reference and turns every
        /// control into a visible plate.
        static let interactive = Color.white.opacity(0.025)
        /// The same, under the pointer. Doubling is what makes a hover read.
        static let interactiveHover = Color.white.opacity(0.06)

        /// Laid over the black of the deployed panel, and nowhere else.
        ///
        /// Four percent: enough that the panel and its blue buttons read as one
        /// object, faint enough that nobody would call it a blue panel. Above
        /// six it stops being a tint and starts being a colour, and the notch
        /// stops looking like a hole.
        static let tint = VibeTheme.Accent.deep.opacity(0.05)
    }

    /// VibeBuddy's own colour: what is interactive, not what is a state.
    ///
    /// It never carries a state — `SessionStateStyle` does that, and red/green
    /// carry the two decisions. Blue means « you can act on this ».
    enum Accent {
        /// `accentBlue` — **the** colour of VibeBuddy, per the brief. Labels,
        /// borders, the word on an accented button.
        static let primary = Color(red: 0, green: 0.659, blue: 1)         // #00A8FF
        /// `accentCyan` — secondary, and it stayed secondary the hard way: used
        /// as the text colour everywhere, it made the panel read cyan rather
        /// than blue. Kept for what sits *on top* of the accent — a chevron, an
        /// arrow — where a lighter tone separates it from the label.
        static let cyan = Color(red: 0.22, green: 0.78, blue: 1)          // #38C7FF
        /// `accentBlueDeep` — for a fill that must stay under text.
        static let deep = Color(red: 0, green: 0.467, blue: 1)            // #0077FF

        /// Behind an accented control. Low enough that the label stays the
        /// thing being read.
        ///
        /// Dropped again, and this time from a measurement rather than from
        /// judgement: the reference's own accented row is `(5,11,21)` over a
        /// `(2,7,14)` panel, which solves to roughly 3 % of blue. At 12 % the
        /// button was four times its model — the « effet néon » in one number.
        static let wash = deep.opacity(0.03)
        static let washHover = deep.opacity(0.08)
        /// The one border that is allowed to be a colour rather than a white.
        ///
        /// 0,55 was neon: on pure black a 55 % blue hairline is the brightest
        /// thing in the panel, brighter than the white text beside it. At 0,38
        /// it still says « this one » without being the first thing the eye
        /// lands on — which should be the question, not the answer.
        static let border = primary.opacity(0.38)
        static let borderHover = primary.opacity(0.55)
    }

    /// Hairlines, and they are **not white**.
    ///
    /// Sampled out of the reference design rather than guessed, by reading the
    /// pixel on each edge and solving for the opacity that produces it over the
    /// panel behind:
    ///
    /// | Edge | Measured | Solves to |
    /// |---|---|---|
    /// | Panel outline | `(21,27,38)` over `(3,5,7)` | 7 % red, 12,5 % blue |
    /// | Card outline | `(20,26,36)` over `(2,6,13)` | 7 % red, 9,5 % blue |
    /// | Separator | `(11,16,24)` over `(3,7,15)` | 3,2 % red, 3,7 % blue |
    ///
    /// Every one of them takes more blue than red, which is why a neutral white
    /// hairline looked wrong against the same panel: at the same lightness it
    /// reads grey where the reference reads like an edge catching the panel's
    /// own colour. `hairline` carries that bias once, and the three opacities
    /// carry only the strength.
    enum Border {
        /// The tint every rule in the panel is drawn with.
        static let hairline = Color(red: 0.72, green: 0.82, blue: 1)

        /// The edge of a thing: a card, a block, the panel itself.
        ///
        /// Calibrated **on the rendered panel**, not on paper. A border is
        /// drawn over the surface it encloses, so it composites twice: at 8,5 %
        /// over a 3 % surface it measured `(26,30,39)` where the reference has
        /// `(20,26,36)`. Solving with the surface included gives 6 %.
        static let subtle = hairline.opacity(0.06)
        /// The panel's own outline, which the reference draws one step stronger
        /// than a card's — `(21,27,38)`.
        static let strong = hairline.opacity(0.10)
        /// A separator only says « these two are not the same paragraph », so
        /// it sits far below an edge. Measured at 3,5 %; drawn at 3, because a
        /// `Divider` is one *point* — two physical pixels on this display —
        /// where the reference is one pixel, and the extra row of pixels reads
        /// as extra light.
        static let divider = hairline.opacity(0.035)
        static let width: CGFloat = 1
    }

    /// Control heights, measured off the reference rather than derived from a
    /// padding.
    ///
    /// The two are **not** the same, and that was the mistake: an answer row is
    /// 43 px tall on the reference and a decision button 32, which at this
    /// render's scale is 48 pt and 36. Section 13 asks for « exactement la même
    /// hauteur » between *Refuser* and *Répondre* — between each other, not with
    /// the list above them.
    ///
    /// Expressed as a height because that is what was measured. Reaching it
    /// through vertical padding means re-deriving it every time the font moves.
    enum Control {
        /// An answer to pick out of a list.
        static let row: CGFloat = 48
        /// A decision at the bottom of the panel.
        static let decision: CGFloat = 36
    }

    /// Four radii, and a pill. A fifth value is a decision nobody made.
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        /// Past half the height of anything this panel draws, so it renders as
        /// a capsule while staying one shape type.
        static let pill: CGFloat = 999
    }

    /// The scale. Values off it — 13, 17, 23 — are how a layout stops lining up.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    /// The type ramp, named by role rather than by size.
    enum Typography {
        /// `AUTORISATION`, `SESSIONS` — uppercase, tracked, quiet.
        static let section = Font.system(size: 11, weight: .semibold)
        static let sectionTracking: CGFloat = 0.8
        /// The tool's name, the product's name.
        static let title = Font.system(size: 15, weight: .semibold)
        static let cardTitle = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        static let secondary = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let badge = Font.system(size: 11, weight: .medium)
        /// Paths, versions, durations, commands. Used sparingly: this is a
        /// panel, not a terminal.
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}
