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

    /// When the current expression began, so transient motions play from their
    /// start rather than from wherever a shared clock happened to be.
    @State private var startedAt = Date()

    public init(
        manifest: BuddyManifest,
        expression: BuddyExpression,
        budget: AnimationBudget
    ) {
        self.manifest = manifest
        self.expression = expression
        self.budget = budget
    }

    private var settings: BuddyManifest.Expression? {
        manifest.expression(expression)
    }

    /// The lower of what the motion needs and what the budget allows.
    ///
    /// An animated expression needs a clock even when its motion is `.none`:
    /// frames advance once a second, so `still` would freeze it on frame one.
    /// One frame per second needs no more than the ambient tier.
    private var tier: AnimationBudget.Tier {
        guard let settings else { return .still }
        if budget.tier == .still { return .still }
        let wanted = settings.frames.count > 1
            ? max(settings.motion.preferredTier.rawValue, AnimationBudget.Tier.ambient.rawValue)
            : settings.motion.preferredTier.rawValue
        return AnimationBudget.Tier(rawValue: min(wanted, budget.tier.rawValue)) ?? .ambient
    }

    private var colour: Color {
        Color(hex: settings?.colour ?? manifest.colour) ?? .primary
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: interval, paused: tier == .still)) { timeline in
            let phase = tier == .still ? 0 : timeline.date.timeIntervalSince(startedAt)
            let motion = (settings?.motion ?? .none).transform(at: phase)

            face(phase: phase)
                .modifier(PixelGrid(colour: colour))
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
            text: settings?.frame(at: phase, secondsPerFrame: BuddyManifest.secondsPerFrame) ?? "",
            colour: colour,
            fontSize: manifest.fontSize,
            pixelSize: Self.pixelSize,
            font: manifest.font
        )
            .fixedSize()
            .shadow(color: colour.opacity(0.95), radius: 1.5)
            .shadow(color: colour.opacity(0.55), radius: 4)
            .shadow(color: colour.opacity(0.30), radius: 9)
    }

    /// Device pixels per rendered pixel.
    ///
    /// Device pixels backing one rendered pixel.
    ///
    /// This coarsens the bitmap; it does **not** change how large the face is
    /// drawn. Raising it makes the blocks chunkier at the same size, and past
    /// about three the kaomoji stop being legible.
    static let pixelSize: CGFloat = 2

    private var interval: Double { tier == .still ? 1 : 1 / tier.rawValue }
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

    /// Points between one grid line and the next.
    static var pitch: CGFloat { BuddyView.pixelSize }

    /// Thickness of the separation. A quarter of the pitch keeps the cell
    /// clearly larger than its border — beyond about a third the grid stops
    /// being a separation and becomes the subject.
    static var lineWidth: CGFloat { max(0.5, pitch / 4) }

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
                            Path(CGRect(x: x, y: 0, width: Self.lineWidth, height: size.height)),
                            with: ink)
                        x += Self.pitch
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: Self.lineWidth)),
                            with: ink)
                        y += Self.pitch
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
