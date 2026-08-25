import CoreGraphics

/// Turns (screen, anchor, desired size) into a window frame.
public enum NotchFrameSolver {
    public static let edgePadding: CGFloat = 10

    /// The notch anchor stays flush at 0 so the pill flows out of the cutout.
    public static let floatingTopGap: CGFloat = 2

    public static let snapFractions: [CGFloat] = [0, 0.5, 1]

    public static let snapThreshold: CGFloat = 60

    /// 56×35 pt for the tigreboite buddy, plus breathing room.
    public static let defaultSlotWidth: CGFloat = 64

    public static let floatingPillHeight: CGFloat = 26

    public static func pillSize(
        geometry: NotchGeometry,
        leftSlot: CGFloat = defaultSlotWidth,
        rightSlot: CGFloat = defaultSlotWidth
    ) -> CGSize {
        guard let notch = geometry.notchSize else {
            return CGSize(width: leftSlot + rightSlot + 40, height: floatingPillHeight)
        }
        return CGSize(width: leftSlot + notch.width + rightSlot, height: notch.height)
    }

    /// Frame for a window of `size` at `fraction` (0 = left edge, 1 = right).
    public static func frame(
        size: CGSize,
        geometry: NotchGeometry,
        fraction: CGFloat
    ) -> CGRect {
        let screen = geometry.screenFrame
        let f = clampFraction(fraction)

        let isCentred = abs(f - 0.5) < 0.001
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
