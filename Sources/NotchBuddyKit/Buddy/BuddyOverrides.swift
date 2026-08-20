import CoreGraphics
import Foundation

/// The user's edits, layered over what the `.buddy` files say.
///
/// # Two sources of truth, and the one place that reconciles them
///
/// D1 asks for a single source of truth per fact, and this breaks it knowingly:
/// what a buddy looks like now comes from a file *and* from this layer. The
/// arbitration (2026-08-20) accepted that in exchange for never writing into a
/// file the user maintains by hand — R1 is the same risk one directory over.
///
/// The mitigation is that the precedence rule lives here, in `apply(to:)`, and
/// nowhere else. No view, no loader and no renderer may re-derive it.
///
/// The escape hatch is `BuddyExportWriter`, which flattens layer and file back
/// into one self-contained `.buddy`. Without it an edit could never be shared,
/// which would quietly close the "buddy per company" direction; with it,
/// sharing becomes deliberate instead of impossible.
public struct BuddyOverrides: Sendable, Equatable, Codable {

    /// One expression's edits. Every field is optional: absent means "whatever
    /// the file says", which is what makes a reset a deletion rather than a
    /// restore.
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

    /// A buddy that exists only in the layer — created in the app, backed by no
    /// file. Stored whole, because there is nothing underneath it to merge with.
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
        // An empty edit is removed rather than stored: otherwise "reset" would
        // leave a record behind that reads as an edit in every listing.
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
            // An edit that empties every frame would render nothing at all;
            // falling back to the file is the honest reading of "no frames".
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

    /// Decoding failures resolve to an empty layer rather than to a trap: this
    /// is stored data that a future version may reshape, and losing edits is
    /// bad where refusing to launch is worse.
    public static func decode(_ data: Data?) -> BuddyOverrides {
        guard let data, let decoded = try? JSONDecoder().decode(BuddyOverrides.self, from: data)
        else { return BuddyOverrides() }
        return decoded
    }
}

extension MotionKind: Encodable {}
