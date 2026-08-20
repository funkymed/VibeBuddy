import CoreGraphics
import Foundation

/// A buddy, as data: a handful of short strings loaded from a file, never
/// compiled in.
/// See RFC-005, "Notes d'implémentation".
public struct BuddyManifest: Sendable, Equatable, Decodable {

    public static let supportedSchema = 3

    public let schema: Int
    public let kind: Kind
    public let id: String
    public let name: String
    public let colour: String
    public let fontSize: CGFloat
    /// Frames per second, for every expression that does not say otherwise.
    public let framesPerSecond: Double
    /// Font family, or nil for the system font.
    /// Of the 29 distinct glyphs in the kaomoji set, Menlo covers 21, Arial
    /// Unicode 20, SF Mono none: forcing a family loses more than it fixes.
    public let font: String?
    public let expressions: [String: Expression]

    public enum Kind: String, Sendable, Equatable, Decodable {
        case ascii
    }

    public struct Expression: Sendable, Equatable, Decodable {
        /// One frame per entry. A single-frame expression simply does not animate.
        public let frames: [String]
        public let motion: MotionKind
        /// Overrides the manifest colour for this state.
        public let colour: String?
        public let framesPerSecond: Double?
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

        public func frame(at phase: Double, secondsPerFrame: Double = 1) -> String {
            guard frames.count > 1 else { return frames.first ?? "" }
            let index = Int(phase / secondsPerFrame) % frames.count
            return frames[max(0, index)]
        }

        /// The longest frame by character count — not necessarily the widest
        /// once measured; layout uses `candidateFrames` instead.
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

    /// Measure every frame, never one candidate per expression: a kaomoji mixes
    /// advance widths, so a shorter frame can be wider. On the shipped emoji
    /// buddy the candidate measured 71 pt where the expression needed 74.
    public var candidateFrames: [(text: String, size: CGFloat)] {
        expressions.values.flatMap { expression in
            expression.frames.map { ($0, size(for: expression)) }
        }
    }

    /// Slowest and fastest a buddy may cycle: one frame per 20 s, and the
    /// `lively` tier above which the budget would refuse to draw.
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

    public func size(for expression: Expression?) -> CGFloat {
        expression?.fontSize ?? fontSize
    }

    public func secondsPerFrame(for expression: Expression?) -> Double {
        1 / rate(for: expression)
    }

    public func rate(for expression: Expression?) -> Double {
        expression?.framesPerSecond ?? framesPerSecond
    }

    public static let defaultFrameRate: Double = 1
}

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
        case .awaiting: return .awaiting
        case .idle:     return .idle
        }
    }
}
