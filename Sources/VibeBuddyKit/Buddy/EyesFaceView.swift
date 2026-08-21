import SwiftUI

/// The EVE-style face: a rounded plate carrying scanlines, two eyes, and a
/// mouth — all drawn as whole pixels rather than as smooth shapes.
///
/// Every feature is rasterised **analytically**: each cell of the plate is
/// tested against the feature's outline and either filled whole or left empty.
/// Nothing is drawn smooth and then quantised, so there is no bitmap to
/// allocate and no half-lit edge cell. On a 58×28 plate at a 2 pt pitch that is
/// 406 tests per frame. See RFC-005, "Notes d'implémentation".
struct EyesFaceView: View {

    let spec: EyeSpec
    let plate: BuddyManifest.FacePlate
    let colour: Color
    let pixelSize: CGFloat
    /// Seconds since the expression was entered.
    let phase: Double

    /// The grain and the tear advance on their own slow tick rather than on
    /// the clock: noise that changes every frame changes the whole path every
    /// frame, and the face itself only moves once a second or two.
    private var tick: Int {
        // A screen that is coming apart comes apart faster: the tear rate rides
        // on `glitch` rather than sitting at the grain's slow tick. At 0.85
        // that is roughly ten changes a second, three frames apart at the full
        // rate — fast enough to read as a signal that will not lock.
        Int(phase * EyeSpec.noiseRate * (1 + 3 * spec.glitch))
    }

    private var rendered: EyeRaster.Frame {
        EyeRaster.frame(
            in: CGSize(width: plate.width, height: plate.height),
            pose: spec.pose,
            animation: EyeAnimation.at(phase: phase, spec: spec),
            pitch: pixelSize,
            grain: spec.grain, glitch: spec.glitch, tick: tick)
    }

    var body: some View {
        let frame = rendered
        return ZStack {
            // Split out on purpose. Nothing in here depends on `phase`, so as
            // its own `View` SwiftUI can compare it frame to frame, find it
            // unchanged, and leave it alone. Inline, it was rebuilt thirty
            // times a second: **127 MB** of `phys_footprint` against a 40 MB
            // budget, where the same face with flat colours sat at 15. Three
            // gradients cost nothing to draw and everything to re-create.
            FaceScreen(plate: plate, colour: colour, pitch: pixelSize)
            CellsShape(cells: frame.grain, pitch: pixelSize)
                .fill(colour.opacity(0.07))
            CellsShape(cells: frame.dim, pitch: pixelSize)
                .fill(colour.opacity(0.34))
            features(frame.lit)
        }
        .frame(width: plate.width, height: plate.height)
        .allowsHitTesting(false)
    }

    // MARK: - Eyes and mouth

    private func features(_ cells: [CGRect]) -> some View {
        let shape = CellsShape(cells: cells, pitch: pixelSize)
        return shape
            // A gradient down the face rather than a flat colour: a lit pixel
            // is brighter at its top than at its bottom on anything that emits.
            // One fill over the whole path, not one per eye — the cost is the
            // same as a flat colour.
            .fill(LinearGradient(
                colors: [colour, colour.opacity(0.72)],
                startPoint: .top, endPoint: .bottom))
            .background { aberration(shape) }
            // **One** shadow, not the three the glyph format used. Measured on
            // scenario B: three cost 38 MB of `phys_footprint` and 5,4 idle
            // wakeups per second, one costs 23 MB and 0,2. Thin strokes need a
            // wide halo; a face of solid cells does not, and a wide halo fills
            // in the gaps that carry the shape — it shut the hole in a working
            // ring outright.
            .shadow(color: colour.opacity(0.55), radius: 2)
    }

    /// Chromatic aberration: the same face, one cell left in red and one cell
    /// right in cyan, under the real one.
    ///
    /// This is what a signal losing its colour lock looks like, and it costs
    /// two more fills of a path that is already built. The alternative — bands
    /// of noise drawn over the top — is louder and reads as decoration.
    @ViewBuilder
    private func aberration(_ shape: CellsShape) -> some View {
        if spec.glitch > 0 {
            let slip = pixelSize * (1 + CGFloat(spec.glitch))
            ZStack {
                shape.fill(Color.red.opacity(0.55 * spec.glitch))
                    .offset(x: -slip)
                shape.fill(Color.cyan.opacity(0.45 * spec.glitch))
                    .offset(x: slip)
            }
        }
    }
}

/// The screen the face is drawn on: the glass, the scanlines that give it its
/// surface, and the fall-off to black at its edges. None of it moves.
///
/// See RFC-005, "Notes d'implémentation".
struct FaceScreen: View {
    let plate: BuddyManifest.FacePlate
    let colour: Color
    let pitch: CGFloat

    /// `AnyShape`, not a `@ViewBuilder`: the builder produces a
    /// `_ConditionalContent`, which is a View and not a Shape, and the screen
    /// has to stay a Shape to be used as a clip.
    private var silhouette: AnyShape {
        plate.silhouette == .oval
            ? AnyShape(Ellipse())
            : AnyShape(RoundedRectangle(cornerRadius: plate.radius, style: .continuous))
    }

    var body: some View {
        ZStack {
            // A radial fall-off rather than flat black: it reads as a curved
            // piece of glass catching a little light in the middle, which is
            // what a screen behind a lens looks like.
            silhouette
                .fill(RadialGradient(
                    colors: [Color(white: 0.10), .black],
                    center: .center, startRadius: 0, endRadius: plate.width * 0.6))
            // The scanlines *are* the screen. They used to be black lines over
            // the glass with a stroked outline around it to say where it
            // stopped. Both are gone: an outline is a border drawn around a
            // face, and a face made of light does not have one. Lit lines in
            // the buddy's own colour give the boundary and the texture in one
            // pass — a raster that happens to be face-shaped, which is what a
            // screen is. Line and gap are the same width: a line thinner than
            // its gap reads as a stripe on something, a line as wide as its gap
            // reads as the thing itself.
            Scanlines(pitch: pitch)
                .fill(colour.opacity(0.13))
            vignette
        }
        // Clipped, not masked: a mask is a second offscreen pass.
        .clipShape(silhouette)
        .allowsHitTesting(false)
    }

    /// How far in from each end the scanlines finish fading, as a fraction of
    /// the screen — derived from a fixed seven points so that a narrower screen
    /// gets a narrower fade rather than a fade that reaches further in.
    private var fade: CGFloat { min(0.30, 7 / max(plate.width, 1)) }

    /// A fall-off to black around the screen.
    ///
    /// It reaches full black inside the corners on purpose: the rounded
    /// rectangle stops having a visible edge, and the face sits in the notch
    /// instead of on a tile laid over it. The eyes are drawn after it, so they
    /// keep their full strength wherever they are looking.
    private var vignette: some View {
        ZStack {
            EllipticalGradient(
                colors: [.clear, .black],
                center: .center,
                // Two attempts either side of this one: 0.30/0.66 started the
                // fall-off beside the eyes and made the face read as small on a
                // large dark tile; 0.62/0.99 left the rounded rectangle with a
                // visible edge again. It is a soft edge, not a spotlight, and
                // not a border either.
                startRadiusFraction: 0.46,
                endRadiusFraction: 0.90)
            // And a horizontal one on top, so every scanline **ends** in black
            // rather than being cut off by the corner it runs into. The
            // elliptical fall-off alone darkens the ends but never quite
            // finishes them: on a wide screen it reaches full black only in the
            // last few points, which reads as a line that stops rather than one
            // that fades out.
            //
            // A fixed **width in points**, not a fraction. As a fraction it
            // followed the screen: narrowing the screen from 80 to 62 brought
            // the fade twelve points closer to the middle, far enough in that a
            // look to the side put an eye inside it — the eye did not clip, it
            // went out.
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .clear, location: fade),
                    .init(color: .clear, location: 1 - fade),
                    .init(color: .black, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// A set of already-rastered cells, as one path.
///
/// **Not a `Canvas`.** A `Canvas` rebuilds a SwiftUI display list on every
/// frame, and this face is redrawn eight times a second: measured on scenario
/// B, the canvases here cost **95 MB** of `phys_footprint` against a 40 MB
/// budget, where the same app with a text buddy sat at 21. A `Shape` goes down
/// the ordinary path-rendering road instead — see the `ImageRenderer` entry in
/// RFC-005's notes for the first time this project paid for a rendering
/// pipeline it did not need.
struct CellsShape: Shape {
    let cells: [CGRect]
    let pitch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // The pixel grid is the gap between cells, not an overlay: insetting
        // each cell gives the matrix for nothing, where a grid layer would have
        // to be drawn full-plate and masked with this one.
        let inset = max(0.25, pitch / 8)
        for cell in cells {
            path.addRect(cell.insetBy(dx: inset, dy: inset).offsetBy(dx: rect.minX, dy: rect.minY))
        }
        return path
    }
}

/// Horizontal bars at the pixel pitch.
struct Scanlines: Shape {
    let pitch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard pitch > 0 else { return path }
        let thickness = max(0.5, pitch / 2)
        var y = rect.minY
        while y < rect.maxY {
            path.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: thickness))
            y += pitch
        }
        return path
    }
}
