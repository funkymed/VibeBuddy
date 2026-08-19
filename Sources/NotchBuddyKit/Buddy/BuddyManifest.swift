import CoreGraphics
import Foundation

/// A buddy, as data: six short strings.
///
/// # How this got here
///
/// It started as bezier paths with an eye rig, then became a pixel grid. Both
/// worked at poster size and lost their meaning at the size that matters.
///
/// The buddy renders into a strip roughly 20 pt tall. At that scale a curve is
/// three grey antialiased pixels, and a 38x24 pixel grid shown at 0.5 pt per
/// cell is one device pixel per cell — technically crisp, practically a smudge.
/// Text is the one thing macOS renders well at 11 pt, because that is what font
/// hinting is *for*.
///
/// `=^^=` is also readable in the manifest, diffable in review, and typeable by
/// anyone who wants a buddy. The pixel format needed a 900-cell hex string and a
/// tool to author it.
///
/// The cost is real and worth naming: no gradients, no per-pixel control, and
/// the face depends on the installed monospaced font. Accepted.
public struct BuddyManifest: Sendable, Equatable, Decodable {

    public static let supportedSchema = 3

    public let schema: Int
    public let kind: Kind
    public let id: String
    public let name: String
    public let colour: String
    /// Point size at which the face is drawn.
    public let fontSize: CGFloat
    /// Frames shown per second, for every expression that does not say
    /// otherwise.
    ///
    /// Expressed as a rate rather than as a delay so that bigger means faster,
    /// which is what someone writing `speed: 4` in a text file expects. The
    /// renderer wants the reciprocal and computes it in one place.
    ///
    /// One per second is the historical default and the value every buddy
    /// written before this option keeps.
    public let framesPerSecond: Double
    /// Font family, or nil for the system font.
    ///
    /// Per buddy rather than global, because the right answer differs by
    /// buddy. Measured on this machine: of 29 distinct glyphs in the kaomoji
    /// set, Menlo covers 21, Arial Unicode 20, SF Mono none, and the only
    /// installed bitmap font none either. Forcing a family on a buddy built
    /// from rare scripts leaves the rest to uncontrolled per-glyph fallback,
    /// which looks worse than letting the system compose it.
    ///
    /// A buddy written in plain ASCII has no such problem and can ask for
    /// whatever it likes.
    public let font: String?
    public let expressions: [String: Expression]

    public enum Kind: String, Sendable, Equatable, Decodable {
        case ascii
    }

    public struct Expression: Sendable, Equatable, Decodable {
        /// One frame per entry, shown one second apart.
        ///
        /// A single-frame expression is legal and simply does not animate — the
        /// format does not need a separate "static" case.
        public let frames: [String]
        public let motion: MotionKind
        /// Overrides the manifest colour for this state.
        public let colour: String?
        /// Overrides the manifest frame rate for this state.
        ///
        /// Worth having for the same reason the size override is: a three-frame
        /// blink and a six-frame typing loop are not the same animation, and a
        /// single rate makes one of them wrong. A `zzz` drifting away wants to
        /// be slower than the buddy it belongs to, not just shorter.
        public let framesPerSecond: Double?
        /// Overrides the manifest size for this state.
        ///
        /// Worth having because these faces differ enormously in density: a
        /// sleeping cat trailing `zzz` and a four-glyph blink want different
        /// point sizes to read as the same weight on screen.
        public let fontSize: CGFloat?

        public init(
            frames: [String], motion: MotionKind,
            colour: String?, fontSize: CGFloat? = nil,
            framesPerSecond: Double? = nil
        ) {
            self.frames = frames; self.motion = motion
            self.colour = colour; self.fontSize = fontSize
            self.framesPerSecond = framesPerSecond
        }

        /// Frame for a moment in time.
        public func frame(at phase: Double, secondsPerFrame: Double = 1) -> String {
            guard frames.count > 1 else { return frames.first ?? "" }
            let index = Int(phase / secondsPerFrame) % frames.count
            return frames[max(0, index)]
        }

        /// The frame that decides the slot's width.
        ///
        /// Sizing from the *current* frame would resize the pill every second,
        /// which reads as the interface twitching rather than the buddy
        /// breathing. The widest frame wins and the layout never moves.
        public var widestFrame: String {
            frames.max { $0.count < $1.count } ?? ""
        }
    }

    // MARK: - Validation

    public enum ValidationError: Error, CustomStringConvertible, Equatable {
        case unsupportedSchema(Int)
        case missingExpression(String)
        case emptyFace(String)
        case badColour(String)
        case badFontSize(CGFloat)
        case badFrameRate(Double)
        case inconsistentWidth(expression: String, expected: Int, found: Int)

        public var description: String {
            switch self {
            case let .unsupportedSchema(v):
                return "schéma \(v) inconnu (supporté : \(BuddyManifest.supportedSchema))"
            case let .missingExpression(n): return "expression « \(n) » absente"
            case let .emptyFace(n): return "« \(n) » : visage vide"
            case let .badColour(c): return "couleur « \(c) » invalide"
            case let .badFontSize(s): return "corps de police invalide : \(s)"
            case let .badFrameRate(r):
                return "vitesse invalide : \(r) (attendu \(BuddyManifest.minimumFrameRate) à \(BuddyManifest.maximumFrameRate) images/s)"
            case let .inconsistentWidth(e, expected, found):
                return "« \(e) » fait \(found) caractères, les autres \(expected)"
            }
        }
    }

    /// Reject anything that would render as nothing.
    ///
    /// **No width check any more.** It existed to stop the pill resizing between
    /// states, and it was the right rule for four-character faces. These
    /// expressions are animations of very different widths — a sleeping cat with
    /// trailing `zzz` against a four-glyph blink — so equal widths are no longer
    /// achievable or desirable. The layout solves it instead, by measuring the
    /// widest frame across every expression once.
    public func validate() throws {
        guard schema == Self.supportedSchema else {
            throw ValidationError.unsupportedSchema(schema)
        }
        guard fontSize >= 4, fontSize <= 64 else {
            throw ValidationError.badFontSize(fontSize)
        }
        guard Self.isValidFrameRate(framesPerSecond) else {
            throw ValidationError.badFrameRate(framesPerSecond)
        }
        guard Self.isValidColour(colour) else { throw ValidationError.badColour(colour) }
        guard expressions["idle"] != nil else {
            throw ValidationError.missingExpression("idle")
        }
        for (name, expression) in expressions {
            guard !expression.frames.isEmpty,
                  expression.frames.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            else { throw ValidationError.emptyFace(name) }
            if let override = expression.colour, !Self.isValidColour(override) {
                throw ValidationError.badColour(override)
            }
            if let rate = expression.framesPerSecond, !Self.isValidFrameRate(rate) {
                throw ValidationError.badFrameRate(rate)
            }
        }
    }

    /// Every frame that could be widest, with the size it will be drawn at.
    ///
    /// Returned as pairs rather than as a single "widest" string, because with
    /// per-expression sizes the longest frame is no longer necessarily the
    /// widest one — a short face at 20 pt beats a long one at 11. Only
    /// measurement can decide, so the layout gets everything it needs to try.
    public var candidateFrames: [(text: String, size: CGFloat)] {
        expressions.values.map { ($0.widestFrame, size(for: $0)) }
    }

    /// Slowest and fastest a buddy may cycle.
    ///
    /// The floor is one frame every twenty seconds — below that an animation is
    /// indistinguishable from a still face and only costs a clock. The ceiling
    /// is the `lively` tier: asking for more would be a rate the budget refuses
    /// to draw, so the file would promise something the renderer silently
    /// ignores.
    public static let minimumFrameRate: Double = 0.05
    public static let maximumFrameRate: Double = 30

    public static func isValidFrameRate(_ rate: Double) -> Bool {
        rate >= minimumFrameRate && rate <= maximumFrameRate
    }

    static func isValidColour(_ hex: String) -> Bool {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        return (text.count == 6 || text.count == 8) && UInt32(text, radix: 16) != nil
    }

    /// Settings for an expression, falling back to `idle`.
    public func expression(_ name: BuddyExpression) -> Expression? {
        expressions[name.rawValue] ?? expressions["idle"]
    }

    /// Point size an expression draws at.
    public func size(for expression: Expression?) -> CGFloat {
        expression?.fontSize ?? fontSize
    }

    /// Seconds between frames for an expression, its own rate first.
    public func secondsPerFrame(for expression: Expression?) -> Double {
        1 / rate(for: expression)
    }

    /// Frames per second an expression draws at.
    public func rate(for expression: Expression?) -> Double {
        expression?.framesPerSecond ?? framesPerSecond
    }

    /// The rate a buddy runs at when the file says nothing — one frame per
    /// second, which is what every buddy written before `speed:` existed does.
    public static let defaultFrameRate: Double = 1
}

/// What the buddy is showing.
public enum BuddyExpression: String, Sendable, Equatable, CaseIterable {
    case sleeping, idle, working, awaiting, finished, failed

    /// The whole mapping from session state to face, in one place.
    public static func from(
        activity: SessionActivity?,
        hasLiveSession: Bool,
        isVisible: Bool
    ) -> BuddyExpression {
        guard isVisible else { return .sleeping }
        guard hasLiveSession, let activity else { return .sleeping }
        switch activity {
        case .working:  return .working
        case .finished: return .finished
        case .failed:   return .failed
        case .idle:     return .idle
        }
    }
}
