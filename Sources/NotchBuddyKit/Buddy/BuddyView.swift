import SwiftUI

/// The buddy on screen: four characters and one clock.
///
/// # One clock, and it can stop
///
/// A single `TimelineView`, paused whenever the budget says `still`. The
/// reference implementation instead scatters eighteen
/// `withAnimation(...).repeatForever` calls across its faces, each installing a
/// `CADisplayLink` that is never torn down — not when the view leaves the
/// screen, not when the window hides. `withAnimation` reads as free at the call
/// site, which is exactly why it accumulates.
///
/// Here the clock is visible in one place and `AnimationBudget` owns its rate.
/// Hidden means rate zero, and zero means no clock at all.
///
/// # Why text
///
/// A monospaced glyph at 12 pt is the one thing macOS renders sharply at this
/// size, because hinting exists for exactly that. The two formats this replaced
/// — beziers, then a pixel grid — were both drawn by hand at poster scale and
/// resolved to a smudge in a 20 pt strip.
public struct BuddyView: View {

    private let manifest: BuddyManifest
    private let expression: BuddyExpression
    @Bindable private var budget: AnimationBudget
    /// Device pixels backing one rendered pixel. A preference rather than a
    /// constant since RFC-010: it changes how coarse the face looks, never how
    /// large it is drawn.
    private let pixelSize: CGFloat
    /// Box the face must stay inside, when the caller knows one.
    ///
    /// The pill's ear is capped (`PillLayout.maxSlotWidth`) and the notch's
    /// height is fixed by the hardware, so a manifest asking for 40 pt has to
    /// give way somewhere. Scaling is the only option that keeps the face a
    /// face: clipping cuts a kaomoji in half, and a half kaomoji reads as a
    /// rendering fault rather than as an expression.
    private let fit: CGSize?

    /// When the current expression began, so transient motions play from their
    /// start rather than from wherever a shared clock happened to be.
    @State private var startedAt = Date()

    public init(
        manifest: BuddyManifest,
        expression: BuddyExpression,
        budget: AnimationBudget,
        pixelSize: Double = Double(BuddyView.defaultPixelSize),
        fit: CGSize? = nil
    ) {
        self.manifest = manifest
        self.expression = expression
        self.budget = budget
        self.pixelSize = CGFloat(pixelSize)
        self.fit = fit
    }

    private var settings: BuddyManifest.Expression? {
        manifest.expression(expression)
    }

    /// The lower of what the motion needs and what the budget allows.
    ///
    /// An animated expression needs a clock even when its motion is `.none`:
    /// frames advance on their own rate, so `still` would freeze it on frame
    /// one. The tier has to clear that rate — a buddy asking for twelve images
    /// per second on an eight-hertz clock drops every third frame, which reads
    /// as stuttering rather than as fast.
    private var tier: AnimationBudget.Tier {
        guard let settings else { return .still }
        if budget.tier == .still { return .still }
        let clock = manifest.rate(for: settings) <= AnimationBudget.Tier.ambient.rawValue
            ? AnimationBudget.Tier.ambient.rawValue
            : AnimationBudget.Tier.lively.rawValue
        let wanted = settings.frames.count > 1
            ? max(settings.motion.preferredTier.rawValue, clock)
            : settings.motion.preferredTier.rawValue
        return AnimationBudget.Tier(rawValue: min(wanted, budget.tier.rawValue)) ?? .ambient
    }

    private var colour: Color {
        Color(hex: settings?.colour ?? manifest.colour) ?? .primary
    }

    /// Width reserved for the face: the widest frame of the *current*
    /// expression, at its own point size.
    ///
    /// Without it the box tracks each frame's own width, so it changes once a
    /// second as the animation cycles. Left-anchoring hides that at the left
    /// edge, but the motion effects — scale, offset, shake — act around the box
    /// centre, so a box that breathes makes the buddy drift while it is
    /// supposed to be bouncing in place.
    ///
    /// Reserved per expression rather than across the whole buddy: the slot
    /// already holds the global maximum, so anything wider here would just be
    /// padding the layout has accounted for twice.
    private var reservedWidth: CGFloat {
        guard let settings else { return 0 }
        let size = manifest.size(for: settings)
        return settings.frames
            .map { PillLayout.measure($0, size: size, weight: .medium, family: manifest.font) }
            .max() ?? 0
    }

    /// How much the face has to shrink to sit inside `fit`.
    ///
    /// Never above 1: a face smaller than its box is drawn at its own size. The
    /// widest frame of the *current* expression decides, so the scale holds for
    /// a whole animation instead of pulsing once a second.
    private var fitScale: CGFloat {
        guard let fit, fit.width > 0, fit.height > 0, let settings else { return 1 }
        let size = manifest.size(for: settings)
        let naturalWidth = reservedWidth
        let naturalHeight = PillLayout.lineHeight(size: size, family: manifest.font)
        guard naturalWidth > 0, naturalHeight > 0 else { return 1 }
        return min(1, fit.width / naturalWidth, fit.height / naturalHeight)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: interval, paused: tier == .still)) { timeline in
            let phase = tier == .still ? 0 : timeline.date.timeIntervalSince(startedAt)
            let motion = (settings?.motion ?? .none).transform(at: phase)

            let fitted = fitScale

            face(phase: phase)
                .modifier(PixelGrid(colour: colour, pitch: pixelSize))
                .frame(width: reservedWidth > 0 ? reservedWidth : nil, alignment: .leading)
                // Fit first, then motion. The other order would make a bouncing
                // buddy grow past the box it was just fitted into.
                .scaleEffect(fitted, anchor: .leading)
                .frame(
                    width: reservedWidth > 0 ? reservedWidth * fitted : nil,
                    alignment: .leading)
                .scaleEffect(motion.scale)
                .offset(x: motion.offset.width + motion.gaze.width * 0.4,
                        y: motion.offset.height)
        }
        .onChange(of: expression) { startedAt = Date() }
        .allowsHitTesting(false)
    }

    /// The glyphs, with a neon bloom.
    ///
    /// Three stacked shadows rather than one: a single wide shadow reads as a
    /// blur, while a tight bright halo over a wide dim one reads as something
    /// emitting light. The tightest is the same colour at full strength — that
    /// is what makes the strokes look thicker and hotter than they are.
    ///
    /// Shadows are cheap here: this is a handful of glyphs, so the blur applies
    /// to a few points rather than to a bitmap.
    private func face(phase: Double) -> some View {
        // The default system font, not monospaced: these faces are kaomoji built
        // from rare scripts and combining marks, and a monospaced face has no
        // advance width for most of them — it falls back per glyph and the
        // alignment ends up worse. Width is handled by measuring, not the font.
        PixelatedText(
            text: settings?.frame(
                at: phase,
                secondsPerFrame: manifest.secondsPerFrame(for: settings)) ?? "",
            colour: colour,
            fontSize: manifest.size(for: settings),
            pixelSize: pixelSize,
            font: manifest.font
        )
            .fixedSize()
            .shadow(color: colour.opacity(0.95), radius: 1.5)
            .shadow(color: colour.opacity(0.55), radius: 4)
            .shadow(color: colour.opacity(0.30), radius: 9)
    }

    /// Device pixels backing one rendered pixel, when nobody says otherwise.
    ///
    /// This coarsens the bitmap; it does **not** change how large the face is
    /// drawn. Raising it makes the blocks chunkier at the same size, and past
    /// about three the kaomoji stop being legible — which is why the preference
    /// that overrides it is clamped rather than free.
    public static let defaultPixelSize: CGFloat = 2

    /// How often the timeline is allowed to tick.
    ///
    /// The tier is a ceiling, not a target. A face whose motion is `.none`
    /// changes only when its frame changes, so ticking at the tier would wake
    /// the view eight times to redraw the same glyphs — the whole point of D3
    /// is that nobody gets to spend wakeups they have no use for. Anything that
    /// actually moves does need the full rate, because its transform is
    /// continuous in phase.
    private var interval: Double {
        guard tier != .still else { return 1 }
        let clock = 1 / tier.rawValue
        guard (settings?.motion ?? MotionKind.none) == MotionKind.none else { return clock }
        return max(clock, manifest.secondsPerFrame(for: settings))
    }
}

/// A pixel grid over whatever it wraps.
///
/// # Grid, not scanlines
///
/// The first version drew horizontal lines only. That is a CRT — and it read as
/// exactly that: stripes. A pixel display is a *matrix*, so the separation has
/// to run both ways or the eye never assembles the cells into squares.
///
/// # Masked to the glyphs
///
/// Ruling the whole pill would only band the black background behind the face.
/// Masking to the content means the grid rides the lit glyphs, which is where a
/// real matrix shows its structure.
///
/// # Pitch follows the pixel size
///
/// The face underneath is already rasterised into blocks of `pixelSize`. A grid
/// at any other pitch beats against those blocks and reads as a rendering fault
/// rather than as structure — so the two are the same number by construction,
/// not by coincidence.
struct PixelGrid: ViewModifier {
    let colour: Color
    /// Points between one grid line and the next. Follows the bitmap's own
    /// coarseness by construction: any other pitch beats against the blocks
    /// underneath and reads as a rendering fault.
    var pitch: CGFloat = BuddyView.defaultPixelSize

    /// Thickness of the separation. A quarter of the pitch keeps the cell
    /// clearly larger than its border — beyond about a third the grid stops
    /// being a separation and becomes the subject.
    var lineWidth: CGFloat { max(0.5, pitch / 4) }

    /// Light enough that the thin strokes of a kaomoji survive. An earlier 0.38
    /// ate `ᓚ₍⑅^- .-^₎` outright.
    static let darkness: Double = 0.30

    func body(content: Content) -> some View {
        content
            .overlay {
                Canvas { context, size in
                    let ink = GraphicsContext.Shading.color(.black.opacity(Self.darkness))
                    var x: CGFloat = 0
                    while x < size.width {
                        context.fill(
                            Path(CGRect(x: x, y: 0, width: lineWidth, height: size.height)),
                            with: ink)
                        x += pitch
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: lineWidth)),
                            with: ink)
                        y += pitch
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
    }
}

public extension Color {
    /// `#RRGGBB` or `#RRGGBBAA`. Anything else is rejected rather than guessed.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard let value = UInt32(text, radix: 16) else { return nil }
        switch text.count {
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255)
        case 8:
            self.init(
                .sRGB,
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                opacity: Double(value & 0xFF) / 255)
        default:
            return nil
        }
    }
}
