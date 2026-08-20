import SwiftUI

/// The buddy on screen: four characters and one clock.
/// See RFC-005, "Notes d'implémentation".
public struct BuddyView: View {

    private let manifest: BuddyManifest
    private let expression: BuddyExpression
    @Bindable private var budget: AnimationBudget
    private let pixelSize: CGFloat
    /// Box the face must stay inside; the face is scaled to it, never clipped.
    private let fit: CGSize?

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

    /// Do not force `.still` on a multi-frame expression: frames advance on the
    /// clock, so a stopped clock freezes it on frame one.
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

    /// Do not size from the current frame: the box changes each second and the
    /// motion effects act around its centre, so the buddy drifts as it bounces.
    private var reservedWidth: CGFloat {
        guard let settings else { return 0 }
        let size = manifest.size(for: settings)
        return settings.frames
            .map { PillLayout.measure($0, size: size, weight: .medium, family: manifest.font) }
            .max() ?? 0
    }

    /// Never above 1.
    private func fitScale(naturalWidth: CGFloat) -> CGFloat {
        guard let fit, fit.width > 0, fit.height > 0, let settings else { return 1 }
        let size = manifest.size(for: settings)
        let naturalHeight = PillLayout.lineHeight(size: size, family: manifest.font)
        guard naturalWidth > 0, naturalHeight > 0 else { return 1 }
        return min(1, fit.width / naturalWidth, fit.height / naturalHeight)
    }

    public var body: some View {
        // Measured once per body, not once per frame: neither depends on
        // `timeline.date`, and each `reservedWidth` walks every frame of the
        // expression through `NSAttributedString`.
        let width = reservedWidth
        let fitted = fitScale(naturalWidth: width)

        return TimelineView(.animation(minimumInterval: interval, paused: tier == .still)) { timeline in
            let phase = tier == .still ? 0 : timeline.date.timeIntervalSince(startedAt)
            let motion = (settings?.motion ?? .none).transform(at: phase)

            face(phase: phase)
                .modifier(PixelGrid(colour: colour, pitch: pixelSize))
                .frame(width: width > 0 ? width : nil, alignment: .leading)
                // Fit first, then motion. The other order would make a bouncing
                // buddy grow past the box it was just fitted into.
                .scaleEffect(fitted, anchor: .leading)
                .frame(
                    width: width > 0 ? width * fitted : nil,
                    alignment: .leading)
                .scaleEffect(motion.scale)
                .offset(x: motion.offset.width + motion.gaze.width * 0.4,
                        y: motion.offset.height)
        }
        .onChange(of: expression) { startedAt = Date() }
        .allowsHitTesting(false)
    }

    private func face(phase: Double) -> some View {
        // Not monospaced: most monospaced families carry no advance width for
        // these rare scripts and fall back per glyph.
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

    /// Device pixels per rendered pixel. Coarsens the bitmap, never the drawn
    /// size; past 3 the kaomoji stop being legible, hence the clamp on the preference.
    public static let defaultPixelSize: CGFloat = 2

    /// The tier is a ceiling, not a target: ticking at the tier would wake the
    /// view eight times to redraw identical glyphs (D3).
    private var interval: Double {
        guard tier != .still else { return 1 }
        let clock = 1 / tier.rawValue
        guard (settings?.motion ?? MotionKind.none) == MotionKind.none else { return clock }
        return max(clock, manifest.secondsPerFrame(for: settings))
    }
}

/// A pixel grid over whatever it wraps.
/// Keep the pitch equal to the bitmap's `pixelSize`: a grid at any other pitch
/// beats against the blocks underneath and reads as a rendering fault.
/// See RFC-005, "Notes d'implémentation".
struct PixelGrid: ViewModifier {
    let colour: Color
    var pitch: CGFloat = BuddyView.defaultPixelSize

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
