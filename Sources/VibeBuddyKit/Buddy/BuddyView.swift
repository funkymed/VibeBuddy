import SwiftUI

/// The buddy on screen: one face and one clock.
/// See RFC-005, "Notes d'implémentation".
public struct BuddyView: View {

    private let manifest: BuddyManifest
    private let expression: BuddyExpression
    @Bindable private var budget: AnimationBudget
    private let pixelSize: CGFloat
    /// Box the face must stay inside; the face is scaled to it, never clipped.
    private let fit: CGSize?

    @State private var startedAt = Date()
    /// The pose being left behind, so a change of expression deforms the face
    /// instead of cutting to it. Nil once the morph has settled.
    @State private var morphFrom: EyePose?
    @State private var morphAt = Date()

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

    private var plate: BuddyManifest.FacePlate { manifest.face }

    /// How long the face takes to reach a new pose. Deliberately brief: the
    /// eyes move in snaps, and a slow morph between two of them would be the
    /// one soft thing left on screen.
    private static let morphDuration: Double = 0.12

    /// Full rate while the face can move, nothing at all when it cannot.
    ///
    /// This was capped at `ambient` on the grounds that a face which only
    /// changes every second or two would redraw the same picture three frames
    /// out of four. That stopped being true when the eyes gained a travel:
    /// during a saccade the picture changes on every frame, and at 8 Hz a
    /// quarter-second crossing gets two of them — which reads as a cut, not as
    /// a move.
    ///
    /// Following `budget.tier` was not enough either: it calls `idle` not busy,
    /// and `idle` is precisely the expression whose eyes wander most.
    ///
    /// So the rate is decided from the face itself. One that never blinks, never
    /// looks anywhere and carries no motion — `sleeping` — has nothing to
    /// redraw and gets **no clock at all**, which is what keeps scenario A at
    /// zero wakeups. Everything else gets the full rate, and SwiftUI skips the
    /// redraw between saccades because the shape comes out equal.
    private var tier: AnimationBudget.Tier {
        guard budget.tier != .still else { return .still }
        guard let spec = settings?.eye else { return .still }
        let still = spec.blink == 0 && spec.gaze == .none
            && (settings?.motion ?? MotionKind.none) == MotionKind.none
        return still ? .still : .lively
    }

    private var colour: Color {
        Color(hex: settings?.colour ?? manifest.colour) ?? .primary
    }

    /// Never above 1.
    private var fitted: CGFloat {
        guard let fit, fit.width > 0, fit.height > 0,
              plate.width > 0, plate.height > 0
        else { return 1 }
        return min(1, fit.width / plate.width, fit.height / plate.height)
    }

    public var body: some View {
        let scale = fitted
        return TimelineView(.animation(minimumInterval: interval, paused: tier == .still)) { timeline in
            let phase = tier == .still ? 0 : timeline.date.timeIntervalSince(startedAt)
            let motion = (settings?.motion ?? .none).transform(at: phase)

            face(phase: phase, now: timeline.date)
                // Fit first, then motion. The other order would make a bouncing
                // face grow past the box it was just fitted into.
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
            EyesFaceView(
                spec: morphed(spec, now: now), plate: plate, colour: colour,
                pixelSize: pixelSize, phase: phase)
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

    /// Device pixels per rendered pixel. Coarsens the raster, never the drawn
    /// size; past 3 the face stops being legible, hence the clamp on the
    /// preference.
    public static let defaultPixelSize: CGFloat = 2

    private var interval: Double {
        tier == .still ? 1 : 1 / tier.rawValue
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
