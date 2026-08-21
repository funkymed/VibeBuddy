import CoreGraphics
import Foundation

/// Turning a face into whole pixels. Pure, and deliberately not part of the
/// view: it is what the tests measure and what `--info` previews, and neither
/// of those should have to build a `View` to ask what the face looks like.
/// See RFC-005, "Notes d'implémentation".
public enum EyeRaster {

    /// One rendered frame: the cells the face lights up, and the fainter ones
    /// the grain lights behind it. Two lists rather than one because they are
    /// drawn at different strengths — a grain cell as bright as an eye is not
    /// grain, it is a broken pixel.
    public struct Frame: Sendable, Equatable {
        /// Full strength: the eye, the iris, the mouth.
        public var lit: [CGRect] = []
        /// Half lit: the body of a filled eye.
        public var dim: [CGRect] = []
        /// What the look was actually worth once the screen had its say. The
        /// animation asks for a distance; the clamp below decides what fits.
        /// Reported because the two differ, and a trace that showed only the
        /// request sent me chasing a bug that was not there.
        public var drift: CGSize = .zero
        /// The digital grain, fainter still. A separate list because it is not
        /// the same strength: at the body's opacity the speckles stop reading
        /// as noise on a screen and start reading as dirt on one.
        public var grain: [CGRect] = []
    }

    /// How brightly one cell comes out.
    public enum Ink: Sendable, Equatable {
        case off, dim, lit
    }

    /// Which whole cells the face lights up.
    public static func cells(
        in size: CGSize, pose: EyePose, animation: EyeAnimation, pitch: CGFloat
    ) -> [CGRect] {
        frame(in: size, pose: pose, animation: animation, pitch: pitch).lit
    }

    public static func frame(
        in size: CGSize, pose: EyePose, animation: EyeAnimation, pitch: CGFloat,
        grain: Double = 0, glitch: Double = 0, tick: Int = 0
    ) -> Frame {
        guard pitch > 0, size.width > 0, size.height > 0 else { return Frame() }
        let eye = pose.eye

        // Squash and stretch: the height the lid takes, the width gives back.
        // Depth multiplies both — leaning in makes the whole face bigger, not
        // just closer to the middle.
        let depth = max(0.2, animation.depth)
        let stretch = eye.width * animation.stretch * animation.smear.width * depth / 2
        // Never below one cell — a shut eye is a line, not an absence.
        var halfHeight = max(
            pitch / 2,
            eye.height * max(0, animation.openness) * animation.smear.height
                * depth * max(0.05, animation.squeeze) / 2)

        // Perspective. A head that turns does not slide its eyes sideways: the
        // eye on the side it turns towards runs away round the curve and
        // foreshortens, the far one comes towards you and widens, and the gap
        // between them closes. Done here, in the raster, rather than with
        // `rotation3DEffect` — that resamples, and a resampled pixel grid is a
        // blurred pixel grid, which is the one thing this look cannot afford.
        let turn = direction(animation.gaze.width)
        let lift = direction(animation.gaze.height)
        // 0.84/1.06, not 0.70/1.10. The stronger pair read as depth on an
        // 80 pt screen with the eyes well apart; at 62 pt and closer together
        // the same 57 % difference turns the near eye into a sliver and the
        // face reads as broken rather than as turned.
        let nearScale = 1 - 0.16 * abs(turn)
        let farScale = 1 + 0.06 * abs(turn)
        // Looking up or down foreshortens both eyes the same way.
        halfHeight *= 1 - 0.16 * abs(lift)
        let leftHalf = (turn < 0 ? nearScale : (turn > 0 ? farScale : 1)) * stretch
        let rightHalf = (turn > 0 ? nearScale : (turn < 0 ? farScale : 1)) * stretch

        // The two eyes stop sharing a height here: one of them can be closed
        // further than the other, which is what sizing someone up looks like.
        let lopsided = max(-1, min(1, animation.lopsided))
        let leftHigh = max(pitch / 2, halfHeight * (1 - max(0, lopsided)))
        let rightHigh = max(pitch / 2, halfHeight * (1 + min(0, lopsided)))

        // Everything lands on the grid, and that is not a detail. A feature
        // whose centre falls between two cells rounds differently on its left
        // and on its right, so it comes out one cell fatter on one side —
        // visible at this size, and the asymmetry flickers as the eyes move.
        let midX = cellCentre(size.width / 2, pitch: pitch)
        let midY = cellCentre(size.height / 2, pitch: pitch)
        let halfGap = quantise(
            (pose.gap / 2 + eye.width / 2) * depth * (1 - 0.14 * abs(turn)), to: pitch)

        // Clamp the look to what the plate can hold, measured **after**
        // snapping and against what the eye actually is on this frame —
        // stretch, smear and depth included. An earlier version compared
        // against a worst-case constant taken from the unsnapped pose, and let
        // the outer eye run one cell off the edge. A clipped eye reads as a
        // fault, not as a look.
        let widest = max(leftHalf, rightHalf)
        let reachX = max(0, size.width / 2 - (halfGap + widest))
        // The roll lifts one eye further than the drift alone, so the vertical
        // clamp has to pay for both or the raised eye clips the top edge.
        let roll = quantise(animation.roll / 2, to: pitch)
        let reachY = max(
            0, size.height / 2 - abs(eye.offsetY) - eye.height * depth / 2 - abs(roll))
        // Toward zero, never away from it: rounding up here would undo the
        // clamp by exactly the cell it was there to keep.
        let driftX = quantiseInward(min(reachX, max(-reachX, animation.gaze.width)), to: pitch)
        let driftY = quantiseInward(min(reachY, max(-reachY, animation.gaze.height)), to: pitch)

        let eyeY = midY + quantise(eye.offsetY, to: pitch) + driftY
        let leftEye = CGPoint(x: midX - halfGap + driftX, y: eyeY + roll)
        let rightEye = CGPoint(x: midX + halfGap + driftX, y: eyeY - roll)
        let mouthCentre = pose.mouth.map {
            CGPoint(x: midX, y: midY + quantise($0.offsetY, to: pitch))
        }

        // A corner radius the grid cannot express is worse than no radius at
        // all. See `drawableRadius`.
        var drawnEye = eye
        drawnEye.radius = drawableRadius(
            eye.radius, halfWidth: min(leftHalf, rightHalf),
            halfHeight: min(leftHigh, rightHigh), pitch: pitch)

        var output = Frame()
        output.drift = CGSize(width: driftX, height: driftY)
        var y: CGFloat = 0
        var row = 0
        while y < size.height {
            // Analogue tearing: a whole row slides sideways by a cell or three.
            // Rows, not pixels — a picture that loses its horizontal lock tears
            // by the line, which is why the fault reads as a screen rather than
            // as a shape coming apart.
            let slip = glitch > 0 ? tear(row: row, tick: tick, amount: glitch, pitch: pitch) : 0
            var x: CGFloat = 0
            while x < size.width {
                let point = CGPoint(x: x + pitch / 2 - slip, y: y + pitch / 2)
                var ink = contains(
                    point, centre: leftEye, halfWidth: leftHalf, halfHeight: leftHigh,
                    feature: drawnEye, mirrored: false)
                if ink == .off {
                    ink = contains(
                        point, centre: rightEye, halfWidth: rightHalf, halfHeight: rightHigh,
                        // Mirrored, not merely counter-tilted: a wing is not
                        // symmetric, so negating the tilt alone would give one
                        // eye the other one's slant.
                        feature: drawnEye, mirrored: true)
                }
                if ink == .off, let mouth = pose.mouth, let centre = mouthCentre {
                    ink = contains(
                        point, centre: centre,
                        halfWidth: mouth.width * depth / 2,
                        halfHeight: mouth.height * depth / 2,
                        feature: mouth, mirrored: false)
                }
                let cell = CGRect(x: x, y: y, width: pitch, height: pitch)
                switch ink {
                case .lit: output.lit.append(cell)
                case .dim: output.dim.append(cell)
                case .off:
                    if grain > 0, speckle(column: Int(x / pitch), row: row, tick: tick) < grain {
                        output.grain.append(cell)
                    }
                }
                x += pitch
            }
            y += pitch
            row += 1
        }
        return output
    }

    /// −1, 0 or +1: the look is one of five places, so its direction is a sign
    /// rather than a slope.
    static func direction(_ value: CGFloat) -> CGFloat {
        value == 0 ? 0 : (value < 0 ? -1 : 1)
    }

    /// How far row `row` has slipped sideways on tick `tick`.
    ///
    /// Bands rather than single rows, and most ticks leave most bands alone:
    /// a picture that tore everywhere at once would read as static, not as a
    /// signal that keeps almost locking.
    static func tear(row: Int, tick: Int, amount: Double, pitch: CGFloat) -> CGFloat {
        let band = row / 2
        guard hashed01(band &* 977 &+ tick, salt: 0x9111) < amount * 0.35 else { return 0 }
        let cells = 1 + Int(hashed01(band &* 31 &+ tick, salt: 0x7A2C) * 3)
        let sign: CGFloat = hashed01(band &+ tick &* 7, salt: 0x1D0F) < 0.5 ? -1 : 1
        return sign * CGFloat(cells) * pitch
    }

    /// Digital grain: sparse, deterministic, and slower than the clock.
    static func speckle(column: Int, row: Int, tick: Int) -> Double {
        hashed01(column &* 73 &+ row &* 131 &+ tick &* 9173, salt: 0x5EED)
    }

    /// The corner radius this grid can actually draw.
    ///
    /// A round eye four cells across is not a circle, it is a **diamond**: the
    /// grid has no cells left to describe a curve with, so the corners eat the
    /// straight edges and what comes out is a lozenge. Measured on `eve` at a
    /// 3 pt pitch, whose 13×12 eye with `r:6` rendered as
    ///
    ///     ·  █       █
    ///       ███     ███
    ///      █████   █████
    ///       ███     ███
    ///        █       █
    ///
    /// Two rules, both about what the grid can hold. One whole cell of straight
    /// edge stays on every side, so there is always a flat to read the shape
    /// against; and the radius lands on a whole number of cells, because half a
    /// cell of curve is either a cell or nothing and the raster has to pick.
    /// Below one cell there is no corner left to round: the eye is a square,
    /// which is the other thing an eye is allowed to be.
    public static func drawableRadius(
        _ radius: CGFloat, halfWidth: CGFloat, halfHeight: CGFloat, pitch: CGFloat
    ) -> CGFloat {
        guard pitch > 0, radius > 0 else { return 0 }
        let straight = min(halfWidth, halfHeight) - pitch
        let capped = min(radius, max(0, straight))
        return (capped / pitch).rounded(.down) * pitch
    }

    /// Whether a point falls inside one feature, after the tilt has been undone
    /// and the mirroring applied.
    ///
    /// `.oval` is measured in points so its corner radius means what it says;
    /// every other shape is measured in the feature's own normalised box, so it
    /// fills whatever width and height it is given. Normalising also means a
    /// shut eye — whose half-height is one cell — squashes its ring or its
    /// crescent down into a bar rather than vanishing.
    public static func contains(
        _ point: CGPoint, centre: CGPoint,
        halfWidth: CGFloat, halfHeight: CGFloat,
        feature: FaceFeature, mirrored: Bool
    ) -> Ink {
        guard halfWidth > 0, halfHeight > 0 else { return .off }
        let dx = point.x - centre.x
        let dy = point.y - centre.y

        let angle = (mirrored ? feature.tilt : -feature.tilt) * .pi / 180
        let rx = dx * cos(angle) - dy * sin(angle)
        let ry = dx * sin(angle) + dy * cos(angle)

        if feature.shape == .oval {
            let r = max(0, min(feature.radius, min(halfWidth, halfHeight)))
            let ax = abs(rx) - (halfWidth - r)
            let ay = abs(ry) - (halfHeight - r)
            if ax <= 0 || ay <= 0 {
                return abs(rx) <= halfWidth && abs(ry) <= halfHeight ? .lit : .off
            }
            return ax * ax + ay * ay <= r * r ? .lit : .off
        }

        let u = (mirrored ? -rx : rx) / halfWidth
        let v = ry / halfHeight
        guard abs(u) <= 1.05, abs(v) <= 1.05 else { return .off }
        return inside(u: u, v: v, feature: feature)
    }

    /// Shape membership in the normalised box: x and y both run −1…1, y down.
    public static func inside(u: CGFloat, v: CGFloat, feature: FaceFeature) -> Ink {
        let t = max(0.05, min(1, feature.thickness))
        switch feature.shape {
        case .oval:
            return .lit  // handled in point space by `contains`

        case .iris:
            let radius = sqrt(u * u + v * v)
            guard radius <= 1 else { return .off }
            // Pupil and iris bright, the rest of the eye half lit. Three
            // strengths on eight cells is as much structure as the grid holds;
            // a fourth would quantise into one of the others.
            if radius <= t * 0.55 { return .lit }
            if abs(radius - 0.62) <= t * 0.5 { return .lit }
            return .dim

        case .arc:
            // The crescent's centreline is a parabola; positive `bend` drops
            // its middle, which is a smile. Scaled by `1 - t` so a thick arc
            // still fits the box it was given.
            let centreline = feature.bend * (1 - u * u) * (1 - t)
            return abs(v - centreline) <= t ? .lit : .off

        case .ring:
            let radius = sqrt(u * u + v * v)
            // The pupil is what tells a ring from a doughnut at this size.
            return abs(radius - (1 - t)) <= t || radius <= t * 0.85 ? .lit : .off

        case .wing:
            // A tapered slash: thick at the outer end, pointed at the inner
            // one. `bend` flips the slant so the same shape can frown or leer.
            let flip: CGFloat = feature.bend < 0 ? -1 : 1
            let a = CGPoint(x: -0.95, y: -0.7 * flip)
            let b = CGPoint(x: 0.9, y: 0.55 * flip)
            let along = progress(CGPoint(x: u, y: v), from: a, to: b)
            let taper = t * (1 - 0.8 * along)
            return distance(CGPoint(x: u, y: v), from: a, to: b) <= taper ? .lit : .off

        case .line:
            return abs(v) <= t && abs(u) <= 1 ? .lit : .off

        case .dots:
            // Squares, not discs: three round dots two cells across are three
            // identical squares anyway, and squares keep the spacing exact.
            for centre in [-0.72, 0, 0.72] as [CGFloat] where abs(u - centre) <= t {
                if abs(v) <= t { return .lit }
            }
            return .off

        case .caret:
            return (distance(CGPoint(x: u, y: v),
                             from: CGPoint(x: -0.9, y: 0.75), to: CGPoint(x: 0, y: -0.75)) <= t
                    || distance(CGPoint(x: u, y: v),
                                from: CGPoint(x: 0, y: -0.75), to: CGPoint(x: 0.9, y: 0.75)) <= t)
                ? .lit : .off

        case .x:
            return (distance(CGPoint(x: u, y: v),
                             from: CGPoint(x: -0.85, y: -0.85), to: CGPoint(x: 0.85, y: 0.85)) <= t
                    || distance(CGPoint(x: u, y: v),
                                from: CGPoint(x: -0.85, y: 0.85), to: CGPoint(x: 0.85, y: -0.85)) <= t)
                ? .lit : .off
        }
    }

    /// How far along `a`→`b` the nearest point to `p` sits, 0…1.
    public static func progress(_ p: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let vx = b.x - a.x, vy = b.y - a.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0 else { return 0 }
        return max(0, min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / lengthSquared))
    }

    public static func distance(_ p: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let s = progress(p, from: a, to: b)
        return hypot(p.x - (a.x + s * (b.x - a.x)), p.y - (a.y + s * (b.y - a.y)))
    }

    /// The centre of the cell `value` falls in.
    public static func cellCentre(_ value: CGFloat, pitch: CGFloat) -> CGFloat {
        (floor(value / pitch) + 0.5) * pitch
    }

    /// The nearest whole number of cells.
    public static func quantise(_ value: CGFloat, to pitch: CGFloat) -> CGFloat {
        (value / pitch).rounded() * pitch
    }

    /// A whole number of cells, never further from zero than the value given.
    public static func quantiseInward(_ value: CGFloat, to pitch: CGFloat) -> CGFloat {
        (value / pitch).rounded(.towardZero) * pitch
    }
}
