import AppKit
import CoreGraphics

/// Where things sit in the collapsed pill.
///
/// # The rule
///
/// The pill is three slots: content, the hardware cutout, content. The middle
/// one is a hole — anything drawn there is invisible — so it is left empty and
/// the two ears carry everything.
///
/// The pill is centred on screen and so is the notch, which makes the naive
/// layout wrong the moment the ears differ in width: centring the *pill* puts
/// the middle slot off the cutout by half the difference. The fix is to shift
/// the whole thing by `(right - left) / 2`, which is what
/// `notchAlignmentOffset` returns.
///
/// # Why widths are measured rather than declared
///
/// The reference implementation hard-codes 56 pt for its buddy and 84 for its
/// usage readout. That works until a buddy has a five-character face, or a font
/// size is changed in a manifest, at which point the content overflows a slot
/// sized for something else.
///
/// Here each slot is measured from what it actually contains, so a manifest
/// that changes `fontSize` or a counter that reaches `×10` widens its own ear
/// without anyone editing a constant.
public struct PillLayout: Sendable, Equatable {

    /// Breathing room either side of a slot's content, so glyphs never touch
    /// the cutout or the pill's rounded edge.
    ///
    /// Trimmed from 10 to 6 when the ears became symmetric: symmetry pads the
    /// narrower ear up to the wider one, so the padding is now paid twice on the
    /// side that has nothing to show. Six points still clears the cutout — the
    /// glyphs never reach the edge — and the pill stops looking inflated.
    public static let slotPadding: CGFloat = 6

    /// Inset on the outer edge of an ear, taken from `slotPadding` rather than
    /// added to it — the slot's measured width already includes both sides, so
    /// adding here would push content past the pill it was measured for.
    public static let outerPadding: CGFloat = 6

    /// Width an ear keeps when it has nothing to show, so the pill still reads
    /// as a shape rather than collapsing onto the notch.
    public static let emptySlotWidth: CGFloat = 18

    /// Widest an ear may get, whatever the buddy asks for.
    ///
    /// Without a ceiling the pill is defined by its content: a manifest with a
    /// long face at 40 pt — which the expression editor now makes trivial to
    /// produce — grows a pill wider than the screen's own notch and turns the
    /// dashboard into a banner. Past this the *buddy* gives way instead, scaled
    /// down to the slot it was given (`BuddyView`, `fit:`).
    ///
    /// 96 pt is roughly the widest face measured on the shipped buddies plus
    /// their padding, so nothing that ships is affected by the cap.
    public static let maxSlotWidth: CGFloat = 96

    public let leftWidth: CGFloat
    public let rightWidth: CGFloat
    public let notchWidth: CGFloat
    public let height: CGFloat

    public var totalWidth: CGFloat { leftWidth + notchWidth + rightWidth }

    /// How far to shift the pill so its middle slot lands on the cutout.
    ///
    /// Zero when the ears match, which is the common case and why this is easy
    /// to forget until the layout drifts.
    public var notchAlignmentOffset: CGFloat { (rightWidth - leftWidth) / 2 }

    public init(leftWidth: CGFloat, rightWidth: CGFloat, notchWidth: CGFloat, height: CGFloat) {
        self.leftWidth = leftWidth
        self.rightWidth = rightWidth
        self.notchWidth = notchWidth
        self.height = height
    }

    /// Lay out for a given buddy and session count.
    public static func resolve(
        geometry: NotchGeometry,
        buddy: BuddyManifest?,
        sessionCount: Int,
        alertText: String? = nil,
        counterFontSize: CGFloat = 11
    ) -> PillLayout {
        let notch = geometry.notchSize
        // Measured across *every* expression, not from the current one. Sizing
        // to what is on screen would resize the pill each second as the
        // animation cycles, and again on every state change — which reads as
        // the interface twitching rather than the buddy moving.
        //
        // Each candidate is measured at its own point size, because an
        // expression may override it: the longest frame is not necessarily the
        // widest once a short face is drawn larger than a long one.
        let left = buddy.map { manifest in
            let widest = manifest.candidateFrames
                .map { measure($0.text, size: $0.size, weight: .medium, family: manifest.font) }
                .max() ?? 0
            return widest + slotPadding * 2
        } ?? emptySlotWidth

        // An alert takes the right ear over from the counter: they say the same
        // kind of thing, and stacking them would make the pill grow twice.
        let rightText = alertText ?? (sessionCount > 0 ? counterText(sessionCount) : nil)
        let right = rightText.map {
            measure($0, size: counterFontSize, weight: .semibold) + slotPadding * 2
        } ?? emptySlotWidth

        // Both ears get the width of the wider one, and neither exceeds the cap.
        //
        // Measuring each ear from its own contents made the pill lopsided — a
        // four-glyph buddy on the left, `×2` on the right — and the fix for that
        // used to be shifting the whole pill so its hole still landed on the
        // cutout (`notchAlignmentOffset`). That works geometrically and looks
        // wrong: the notch is symmetric, and a shape hanging further out on one
        // side reads as misaligned even when it is exactly aligned.
        //
        // Equal ears cost a few points of width on the narrower side and buy a
        // shape that is symmetric about the cutout by construction — the offset
        // is then zero, not corrected.
        let slot = min(max(left, right, emptySlotWidth), maxSlotWidth)

        return PillLayout(
            leftWidth: slot,
            rightWidth: slot,
            // Without a cutout there is no hole to straddle, so the two ears sit
            // side by side with a token gap.
            notchWidth: notch?.width ?? 24,
            height: notch?.height ?? NotchFrameSolver.floatingPillHeight
        )
    }

    public static func counterText(_ count: Int) -> String { "×\(count)" }

    /// Box a slot actually offers its content, padding removed.
    ///
    /// The buddy is scaled to this rather than clipped to it: a face cut in half
    /// reads as a rendering fault, a face drawn slightly smaller reads as a
    /// face.
    public func contentBox(vertical inset: CGFloat = 4) -> CGSize {
        CGSize(
            width: max(0, leftWidth - PillLayout.slotPadding * 2),
            height: max(0, height - inset * 2))
    }

    /// Line height of a face at a given point size, in the font that will draw
    /// it — the vertical half of the fit calculation.
    public static func lineHeight(size: CGFloat, family: String?) -> CGFloat {
        let font = family.flatMap { NSFont(name: $0, size: size) }
            ?? NSFont.systemFont(ofSize: size, weight: .medium)
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// Rendered width of a string, in points.
    ///
    /// Measured through AppKit rather than estimated from character count: a
    /// monospaced face still has per-font advance widths, and guessing produces
    /// a slot that is either clipped or padded by a few points on every machine
    /// with a different default.
    public static func measure(
        _ text: String, size: CGFloat, weight: NSFont.Weight, family: String? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        // Measured in the font that will actually draw it. Measuring in one
        // family and rendering in another is how a slot ends up clipped.
        let font = family.flatMap { NSFont(name: $0, size: size) }
            ?? NSFont.systemFont(ofSize: size, weight: weight)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        return ceil(attributed.size().width)
    }
}
