import CoreGraphics
import Foundation

/// The user's edits, layered over what the `.buddy` files say. Do not re-derive
/// the precedence rule anywhere else: it lives in `apply(to:)`.
/// See RFC-005, "Notes d'implémentation".
public struct BuddyOverrides: Sendable, Equatable, Codable {

    /// One expression's edits. An absent field means "whatever the file says".
    public struct Expression: Sendable, Equatable, Codable {
        public var frames: [String]?
        public var colour: String?
        public var fontSize: Double?
        public var framesPerSecond: Double?
        public var motion: MotionKind?

        public init(
            frames: [String]? = nil, colour: String? = nil, fontSize: Double? = nil,
            framesPerSecond: Double? = nil, motion: MotionKind? = nil
        ) {
            self.frames = frames; self.colour = colour; self.fontSize = fontSize
            self.framesPerSecond = framesPerSecond; self.motion = motion
        }

        public var isEmpty: Bool {
            frames == nil && colour == nil && fontSize == nil
                && framesPerSecond == nil && motion == nil
        }
    }

    /// A buddy backed by no file. Stored whole: nothing underneath to merge with.
    public struct Created: Sendable, Equatable, Codable {
        public var name: String
        public var colour: String
        public var fontSize: Double
        public var framesPerSecond: Double
        public var font: String?
        public var expressions: [String: Expression]

        public init(
            name: String, colour: String = "#FFBB00", fontSize: Double = 15,
            framesPerSecond: Double = 1, font: String? = nil,
            expressions: [String: Expression] = [:]
        ) {
            self.name = name; self.colour = colour; self.fontSize = fontSize
            self.framesPerSecond = framesPerSecond; self.font = font
            self.expressions = expressions
        }
    }

    /// buddy id → expression name → edits.
    public var edits: [String: [String: Expression]] = [:]
    /// buddy id → a buddy with no file behind it.
    public var created: [String: Created] = [:]

    public init() {}

    // MARK: - Reading

    public func expression(_ name: String, of buddyID: String) -> Expression? {
        edits[buddyID]?[name]
    }

    public func hasEdits(for buddyID: String) -> Bool {
        !(edits[buddyID]?.isEmpty ?? true)
    }

    // MARK: - Writing

    public mutating func set(_ edit: Expression, for name: String, of buddyID: String) {
        // Remove rather than store: an empty edit still reads as an edit.
        if edit.isEmpty {
            edits[buddyID]?.removeValue(forKey: name)
            if edits[buddyID]?.isEmpty == true { edits.removeValue(forKey: buddyID) }
        } else {
            edits[buddyID, default: [:]][name] = edit
        }
    }

    public mutating func reset(_ name: String, of buddyID: String) {
        edits[buddyID]?.removeValue(forKey: name)
        if edits[buddyID]?.isEmpty == true { edits.removeValue(forKey: buddyID) }
    }

    public mutating func resetAll(of buddyID: String) {
        edits.removeValue(forKey: buddyID)
    }

    // MARK: - Merge

    /// The manifest as the user has it: file first, layer on top.
    public func apply(to manifest: BuddyManifest) -> BuddyManifest {
        guard let forBuddy = edits[manifest.id], !forBuddy.isEmpty else { return manifest }

        var expressions = manifest.expressions
        for (name, edit) in forBuddy {
            let base = expressions[name]
            let frames = edit.frames ?? base?.frames ?? []
            // An edit that empties every frame would render nothing: fall back.
            guard !frames.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).isEmpty
            else { continue }
            expressions[name] = BuddyManifest.Expression(
                frames: frames,
                motion: edit.motion ?? base?.motion ?? MotionKind.default(for: name),
                colour: edit.colour ?? base?.colour,
                fontSize: edit.fontSize.map { CGFloat($0) } ?? base?.fontSize,
                framesPerSecond: edit.framesPerSecond ?? base?.framesPerSecond)
        }

        return BuddyManifest(
            schema: manifest.schema, kind: manifest.kind, id: manifest.id,
            name: manifest.name, colour: manifest.colour, fontSize: manifest.fontSize,
            framesPerSecond: manifest.framesPerSecond, font: manifest.font,
            expressions: expressions)
    }

    /// A manifest for a buddy that has no file.
    public func manifest(forCreated id: String) -> BuddyManifest? {
        guard let created = created[id] else { return nil }
        var expressions: [String: BuddyManifest.Expression] = [:]
        for (name, edit) in created.expressions {
            let frames = edit.frames ?? []
            guard !frames.isEmpty else { continue }
            expressions[name] = BuddyManifest.Expression(
                frames: frames,
                motion: edit.motion ?? MotionKind.default(for: name),
                colour: edit.colour,
                fontSize: edit.fontSize.map { CGFloat($0) },
                framesPerSecond: edit.framesPerSecond)
        }
        guard expressions["idle"] != nil else { return nil }
        return BuddyManifest(
            schema: BuddyManifest.supportedSchema, kind: .ascii, id: id,
            name: created.name, colour: created.colour,
            fontSize: CGFloat(created.fontSize),
            framesPerSecond: created.framesPerSecond, font: created.font,
            expressions: expressions)
    }

    // MARK: - Storage

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// Decoding failures resolve to an empty layer, never to a trap.
    public static func decode(_ data: Data?) -> BuddyOverrides {
        guard let data, let decoded = try? JSONDecoder().decode(BuddyOverrides.self, from: data)
        else { return BuddyOverrides() }
        return decoded
    }
}

extension MotionKind: Encodable {}
