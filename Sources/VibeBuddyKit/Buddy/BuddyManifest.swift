import CoreGraphics
import Foundation

/// A buddy, as data: a screen and six faces, loaded from a file, never compiled
/// in.
/// See RFC-005, "Notes d'implémentation".
public struct BuddyManifest: Sendable, Equatable {

    public static let supportedSchema = 3

    public let schema: Int
    public let id: String
    public let name: String
    public let colour: String
    /// The screen the faces are drawn on.
    public let face: FacePlate
    public let expressions: [String: Expression]

    /// The screen. Absent from the first version of the format, which drew
    /// glyphs and had no screen at all.
    public struct FacePlate: Sendable, Equatable, Codable {
        /// A screen is either a rounded rectangle or an oval. Two cases rather
        /// than "radius large enough": an ellipse is not a rounded rectangle at
        /// any radius, and the difference is visible at the corners.
        public enum Silhouette: String, Sendable, Equatable, Codable {
            case rounded, oval
        }

        public var width: CGFloat
        public var height: CGFloat
        public var radius: CGFloat
        public var silhouette: Silhouette

        public init(
            width: CGFloat = 80, height: CGFloat = 30, radius: CGFloat = 15,
            silhouette: Silhouette = .oval
        ) {
            self.width = width; self.height = height
            self.radius = radius; self.silhouette = silhouette
        }
    }

    public struct Expression: Sendable, Equatable {
        public let eye: EyeSpec
        /// Movement of the whole screen. A reaction, never a loop.
        public let motion: MotionKind
        /// Overrides the manifest colour for this state.
        public let colour: String?

        public init(eye: EyeSpec, motion: MotionKind, colour: String?) {
            self.eye = eye; self.motion = motion; self.colour = colour
        }
    }

    public init(
        schema: Int, id: String, name: String, colour: String,
        face: FacePlate, expressions: [String: Expression]
    ) {
        self.schema = schema; self.id = id; self.name = name
        self.colour = colour; self.face = face; self.expressions = expressions
    }

    // MARK: - Validation

    public enum ValidationError: Error, CustomStringConvertible, Equatable {
        case unsupportedSchema(Int)
        case missingExpression(String)
        case badColour(String)
        case badFace

        public var description: String {
            switch self {
            case let .unsupportedSchema(v):
                return "schéma \(v) inconnu (supporté : \(BuddyManifest.supportedSchema))"
            case let .missingExpression(n): return "expression « \(n) » absente"
            case let .badColour(c): return "couleur « \(c) » invalide"
            case .badFace:
                return "« face: » hors bornes (largeur 8–\(Int(PillLayout.maxSlotWidth)), hauteur ≥ 6)"
            }
        }
    }

    /// Reject anything that would render as nothing.
    public func validate() throws {
        guard schema == Self.supportedSchema else {
            throw ValidationError.unsupportedSchema(schema)
        }
        guard Self.isValidColour(colour) else { throw ValidationError.badColour(colour) }
        guard expressions["idle"] != nil else {
            throw ValidationError.missingExpression("idle")
        }
        guard face.width >= 8, face.height >= 6,
              face.width <= PillLayout.maxSlotWidth, face.radius >= 0
        else { throw ValidationError.badFace }
        for expression in expressions.values {
            if let override = expression.colour, !Self.isValidColour(override) {
                throw ValidationError.badColour(override)
            }
        }
    }

    static func isValidColour(_ hex: String) -> Bool {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        return (text.count == 6 || text.count == 8) && UInt32(text, radix: 16) != nil
    }

    /// The same buddy, larger or smaller. The pill is measured from
    /// `face.width`, so this is what makes the collapsed pill's width a
    /// preference rather than a constant.
    // `scaled(_:)` was removed on 2026-08-21, and is not to come back.
    //
    // It multiplied the plate and every pose by the pill's size preference. But
    // `EyeRaster` lights whole cells: at another size the same face lands on a
    // different number of them, so the eyes came out a different *shape*, not a
    // bigger one. The pill now widens its own ear and leaves the manifest at
    // the size its author wrote. See `PillLayout.resolve`.

    /// Settings for an expression, falling back to `idle`.
    public func expression(_ name: BuddyExpression) -> Expression? {
        expressions[name.rawValue] ?? expressions["idle"]
    }
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
