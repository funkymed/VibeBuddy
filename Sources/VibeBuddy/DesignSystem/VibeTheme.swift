import SwiftUI

/// The panel's design tokens: surfaces, accent, radii, spacing, typography.
enum VibeTheme {
    /// Depth, by how far a surface is lifted off the black.
    enum Surface {
        /// A block the content is poured into.
        static let sunken = Color.white.opacity(0.03)
        /// Something you can click that is not asking to be clicked. Measured at 2,5 %;
        /// a grey at 10 % turns every control into a visible plate.
        static let interactive = Color.white.opacity(0.025)
        /// Under the pointer.
        static let interactiveHover = Color.white.opacity(0.10)
        /// Laid over the black of the deployed panel, and nowhere else.
        static let tint = VibeTheme.Accent.deep.opacity(0.05)
    }

    /// VibeBuddy's own colour: what is interactive, never what is a state.
    enum Accent {
        /// `accentBlue` — the colour of the product.
        static let primary = Color(red: 0, green: 0.659, blue: 1)         // #00A8FF
        /// `accentCyan` — secondary, for what sits *on top* of the accent: a chevron, an
        /// arrow.
        static let cyan = Color(red: 0.22, green: 0.78, blue: 1)          // #38C7FF
        /// `accentBlueDeep` — for a fill that must stay under text.
        static let deep = Color(red: 0, green: 0.467, blue: 1)            // #0077FF

        /// Behind an accented control. Measured: the reference's accented row is
        /// `(5,11,21)` over `(2,7,14)`, about 3 % of blue. At 12 % it was four times its
        /// model — the « effet néon » in one number.
        static let wash = deep.opacity(0.03)
        static let washHover = deep.opacity(0.08)
        /// 0,55 was neon: on pure black a 55 % blue hairline outshines the white text
        /// beside it.
        static let border = primary.opacity(0.38)
        static let borderHover = primary.opacity(0.55)
    }

    /// Light. This repository has paid for unmeasured light three times: three stacked
    /// shadows on the face cost 38 Mo and 5,4 wakeups/s where one costs 23 Mo and 0,2 ;
    /// three gradients inside a phase-dependent body cost 127 Mo ; `ImageRenderer` for a
    /// dozen glyphs cost 101 Mo against a 40 Mo budget.
    enum Glow {
        /// 0,55, measured rather than judged. At 0,30 the halo came out one level
        /// above the panel — `(4,8,15)` against `(4,8,14)` — which is to say invisible.
        /// A blurred colour spread over a radius loses its opacity to the spread; on a
        /// near-black panel the number has to be far higher than the « 10 % » a design
        /// brief writes for a light background.
        static let outer = Accent.primary.opacity(0.55)
        static let radius: CGFloat = 6
        /// The pooled edge, drawn as a stroke rather than a second blur.
        static let inner = Accent.primary.opacity(0.16)
        /// A refusal lights in its own colour, and only under the pointer.
        static let deny = PermissionInk.removed.opacity(0.45)
    }

    /// Hairlines, and they are not white. | Edge | Measured | Solves to |
    /// |---|---|---| | Panel outline | `(21,27,38)` over `(3,5,7)` | 7 % red, 12,5 %
    /// blue | | Card outline | `(20,26,36)` over `(2,6,13)` | 7 % red, 9,5 % blue | |
    /// Separator | `(11,16,24)` over `(3,7,15)` | 3,2 % red, 3,7 % blue |
    enum Border {
        static let hairline = Color(red: 0.72, green: 0.82, blue: 1)

        /// The edge of a thing: a card, a block, the panel itself. Calibrated on the
        /// rendered panel, where a border composites over the surface it encloses: at
        /// 8,5 % over a 3 % surface it measured `(26,30,39)` where the reference has
        /// `(20,26,36)`. Solving with the surface included gives 6 %.
        static let subtle = hairline.opacity(0.06)
        /// The panel's own outline, one step stronger — `(21,27,38)`.
        static let strong = hairline.opacity(0.10)
        /// A separator only says « these two are not the same paragraph ». Measured at
        /// 3,5 %, drawn at 3: a `Divider` is one *point*, two physical pixels, where the
        /// reference is one.
        static let divider = hairline.opacity(0.035)
        static let width: CGFloat = 1
    }

    /// Control heights, measured off the reference rather than derived from a padding.
    /// An answer row and a decision button are not the same height: an answer row is
    /// 43 px on the reference and a decision button 32, which at this render's scale is
    /// 48 pt and 36.
    enum Control {
        static let row: CGFloat = 48
        static let decision: CGFloat = 36
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        /// Past half the height of anything drawn here, so it renders as a capsule while
        /// staying one shape type.
        static let pill: CGFloat = 999
    }

    /// The scale.
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
        static let section = Font.system(size: 11, weight: .semibold)
        static let sectionTracking: CGFloat = 0.8
        static let title = Font.system(size: 15, weight: .semibold)
        static let cardTitle = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        static let secondary = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let badge = Font.system(size: 11, weight: .medium)
        /// Paths, versions, durations, commands.
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}
