import SwiftUI

/// The buddy on screen: one face and one clock.
public struct BuddyView: View {
    private let manifest: BuddyManifest
    private let expression: BuddyExpression
    @Bindable private var budget: AnimationBudget
    /// Box the face must stay inside; the face is scaled to it, never clipped.
    private let fit: CGSize?
    private let gaze: PointerGaze?

    @State private var startedAt = Date()
    /// The pose being left behind, so a change of expression deforms the face instead of
    /// cutting to it.
    @State private var morphFrom: EyePose?
    @State private var morphAt = Date()

    public init(
        manifest: BuddyManifest,
        expression: BuddyExpression,
        budget: AnimationBudget,
        fit: CGSize? = nil,
        gaze: PointerGaze? = nil
    ) {
        self.manifest = manifest
        self.expression = expression
        self.budget = budget
        self.fit = fit
        self.gaze = gaze
    }

    private var settings: BuddyManifest.Expression? {
        manifest.expression(expression)
    }

    private var plate: BuddyManifest.FacePlate { manifest.face }

    /// How long the face takes to reach a new pose.
    private static let morphDuration: Double = 0.12

    /// Full rate while the face can move, nothing at all when it cannot. That stopped
    /// being true when the eyes gained a travel: during a saccade the picture changes on
    /// every frame, and at 8 Hz a quarter-second crossing gets two of them — which reads
    /// as a cut, not as a move.
    private var tier: AnimationBudget.Tier {
        guard budget.tier != .still else { return .still }
        // The mood needs the clock even when the spec does not: `sleeping` is a face
        // that cannot move (no blink, no gaze, no motion), and a paused timeline froze
        // its date — so a chase from sleep borrowed the finished eyes and then rendered
        // its progress against a date in the past: eyes swapped, zero pink, zero
        // pursuit. The body is re-evaluated on every gaze revision, so this flips to
        // lively on the first sample of the gesture and back once the mood has faded.
        if gaze?.isAnimating() == true { return .lively }
        guard let spec = settings?.eye else { return .still }
        let still = spec.blink == 0 && spec.gaze == .none
            && (settings?.motion ?? MotionKind.none) == MotionKind.none
        return still ? .still : .lively
    }

    private var colour: Color {
        Color(hex: settings?.colour ?? manifest.colour) ?? .primary
    }

    /// The box is the size the face is drawn at, up or down.
    private var fitted: CGFloat {
        guard let fit, fit.width > 0, fit.height > 0,
              plate.width > 0, plate.height > 0
        else { return 1 }
        return min(fit.width / plate.width, fit.height / plate.height)
    }

    public var body: some View {
        let scale = fitted
        return TimelineView(.animation(minimumInterval: interval, paused: tier == .still)) { timeline in
            let phase = tier == .still ? 0 : timeline.date.timeIntervalSince(startedAt)
            let motion = (settings?.motion ?? .none).transform(at: phase)

            face(phase: phase, now: timeline.date)
                // Fit first, then motion.
                .scaleEffect(scale, anchor: .leading)
                .frame(width: plate.width * scale, height: plate.height * scale)
                .scaleEffect(motion.scale)
                .offset(x: motion.offset.width, y: motion.offset.height)
        }
        .onChange(of: expression) { previous, _ in
            morphFrom = manifest.expressions[previous.rawValue]?.eye.pose
            morphAt = Date()
            startedAt = Date()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func face(phase: Double, now: Date) -> some View {
        if let spec = settings?.eye {
            // Read once per frame, here: `mood` advances a small state machine, and
            // calling it twice in one frame would count one double-take as two.
            let mood = gaze?.mood(at: now) ?? .resting
            // A mood may borrow another expression's eyes.
            let worn = mood.borrowedExpression
                .flatMap { manifest.expression($0)?.eye } ?? spec
            EyesFaceView(
                spec: morphed(worn, now: now), plate: plate,
                // A mood may insist on its own colour.
                colour: mood.tint.flatMap { Color(hex: $0) }
                    .map { Color.mix(colour, $0, mood.tintStrength) } ?? colour,
                pixelSize: Self.pixelSize, phase: phase,
                mood: mood, look: gaze?.look() ?? .level)
        } else {
            Color.clear.frame(width: plate.width, height: plate.height)
        }
    }

    /// The pose on its way from the previous expression to this one.
    private func morphed(_ spec: EyeSpec, now: Date) -> EyeSpec {
        guard let from = morphFrom else { return spec }
        let elapsed = now.timeIntervalSince(morphAt) / Self.morphDuration
        guard elapsed < 1 else { return spec }
        let t = max(0, elapsed)
        var morphing = spec
        morphing.pose = EyePose.lerp(from, spec.pose, CGFloat(1 - pow(1 - t, 2)))
        return morphing
    }

    /// Device pixels per rendered pixel.
    public static let pixelSize: CGFloat = 3

    private var interval: Double {
        tier == .still ? 1 : 1 / tier.rawValue
    }
}

public extension Color {
    /// `#RRGGBB` or `#RRGGBBAA`.
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

public extension Color {
    /// `t` of the way from `a` to `b`, in sRGB.
    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let k = min(max(t, 0), 1)
        guard k > 0 else { return a }
        guard k < 1 else { return b }
        guard let from = NSColor(a).usingColorSpace(.sRGB),
              let to = NSColor(b).usingColorSpace(.sRGB),
              let blended = from.blended(withFraction: CGFloat(k), of: to)
        else { return k < 0.5 ? a : b }
        return Color(nsColor: blended)
    }
}
