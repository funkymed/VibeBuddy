import CoreGraphics

/// Turns (screen, anchor, desired size) into a window frame.
///
/// Pure and free of AppKit types beyond `CGRect`, so every positioning rule —
/// clamping, snapping, the notched-screen flush rule — is testable without a
/// display attached. In the reference implementation this arithmetic lives
/// inside the `NSPanel` subclass, which is why its edge cases were fixed with
/// flags instead of tests.
public enum NotchFrameSolver {

    /// Distance from the screen edge kept for non-centred anchors.
    public static let edgePadding: CGFloat = 10

    /// Vertical breathing room for anchors that are not the hardware notch.
    /// The notch anchor itself stays flush at 0 so the pill appears to flow out
    /// of the cutout rather than hang below it.
    public static let floatingTopGap: CGFloat = 2

    /// Horizontal positions the pill snaps to, as a fraction of usable width.
    public static let snapFractions: [CGFloat] = [0, 0.5, 1]

    /// How close (in points) a drag must land to a snap fraction to be caught.
    public static let snapThreshold: CGFloat = 60

    /// Default width of one content slot flanking the notch.
    ///
    /// Sized for the buddy — RFC-005 settled on 56×35 pt for the tigreboite
    /// manifest — plus a little breathing room.
    public static let defaultSlotWidth: CGFloat = 64

    /// Height of the pill on a display that has no notch to match.
    public static let floatingPillHeight: CGFloat = 26

    /// Size of the collapsed pill.
    ///
    /// **The pill is derived from the notch, never a constant.** A pill exactly
    /// as wide and tall as the cutout is black-on-black: perfectly correct, and
    /// invisible. This was only caught by looking at a screenshot — no unit test
    /// or memory measurement can see it.
    ///
    /// So the pill spans `leftSlot + notchWidth + rightSlot`: the middle lands
    /// on the hardware cutout and stays empty, and the content lives in the two
    /// ears that overhang it. Height matches the notch exactly, so the whole
    /// thing reads as one shape flowing out of the hole.
    public static func pillSize(
        geometry: NotchGeometry,
        leftSlot: CGFloat = defaultSlotWidth,
        rightSlot: CGFloat = defaultSlotWidth
    ) -> CGSize {
        guard let notch = geometry.notchSize else {
            // No cutout to hug: a plain floating lozenge.
            return CGSize(width: leftSlot + rightSlot + 40, height: floatingPillHeight)
        }
        return CGSize(width: leftSlot + notch.width + rightSlot, height: notch.height)
    }

    /// Frame for a window of `size`, anchored at `fraction` across `geometry`.
    ///
    /// `fraction` is 0 at the left edge and 1 at the right, measured on the
    /// space the window can occupy — so the window is always fully on screen
    /// without the caller clamping anything.
    public static func frame(
        size: CGSize,
        geometry: NotchGeometry,
        fraction: CGFloat
    ) -> CGRect {
        let screen = geometry.screenFrame
        let f = clampFraction(fraction)

        let isCentred = abs(f - 0.5) < 0.001
        // Flush to the top edge only when the pill sits on the notch itself.
        let gap = (geometry.hasNotch && isCentred) ? 0 : floatingTopGap
        let padding = isCentred ? 0 : edgePadding

        let usable = max(0, screen.width - size.width - padding * 2)
        let x = screen.minX + padding + usable * f
        let y = screen.maxY - size.height - gap

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    public static func clampFraction(_ f: CGFloat) -> CGFloat {
        f.isFinite ? min(max(f, 0), 1) : 0.5
    }

    /// Fraction corresponding to a window whose left edge sits at `originX`.
    /// The inverse of `frame(size:geometry:fraction:)`, used while dragging.
    public static func fraction(
        forOriginX originX: CGFloat,
        size: CGSize,
        geometry: NotchGeometry
    ) -> CGFloat {
        let screen = geometry.screenFrame
        let usable = screen.width - size.width - edgePadding * 2
        guard usable > 0 else { return 0.5 }
        return clampFraction((originX - screen.minX - edgePadding) / usable)
    }

    /// Snap a dragged fraction to the nearest magnet, if close enough.
    ///
    /// The threshold is expressed in points rather than in fraction units so it
    /// feels identical on a 13" laptop and a 34" ultrawide — a fixed fraction
    /// would make magnets four times stickier on the wide display.
    public static func snap(
        fraction: CGFloat,
        size: CGSize,
        geometry: NotchGeometry
    ) -> CGFloat {
        let usable = geometry.screenFrame.width - size.width - edgePadding * 2
        guard usable > 0 else { return 0.5 }
        let thresholdInFractions = snapThreshold / usable

        let f = clampFraction(fraction)
        var best = f
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for candidate in snapFractions {
            let d = abs(candidate - f)
            if d < bestDistance {
                bestDistance = d
                best = candidate
            }
        }
        return bestDistance <= thresholdInFractions ? best : f
    }
}
