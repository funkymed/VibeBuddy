import Foundation

/// Finds and validates buddies, and never returns nothing.
///
/// A manifest is a file the user can edit, copy, or receive from their company.
/// Every failure mode here — missing, malformed, wrong schema, empty — resolves
/// to the built-in buddy. An app that shows no face because a JSON file has a
/// trailing comma is worse than one that shows the wrong face.
public struct BuddyLoader: Sendable {

    /// Why a manifest could not be used. A value rather than a trap: a bad file
    /// must degrade to the built-in buddy, never take the app down.
    public enum LoadError: Error, CustomStringConvertible, Equatable {
        case notFound
        case invalidJSON(String)
        case invalid(BuddyManifest.ValidationError)

        public var description: String {
            switch self {
            case .notFound: return "introuvable"
            case let .invalidJSON(detail): return "JSON illisible : \(detail)"
            case let .invalid(error): return error.description
            }
        }
    }


    /// Where buddies live, discovered at launch.
    public static var searchPath: String {
        (SupportDirectory.path as NSString).appendingPathComponent("buddies")
    }

    public struct Loaded: Sendable, Equatable {
        public let manifest: BuddyManifest
        /// Nil for the built-in buddy.
        public let path: String?
        public let isFallback: Bool
    }

    public private(set) var problems: [String] = []

    public init() {}

    /// Load `id`, or the built-in buddy if it cannot be loaded.
    public mutating func load(id: String?) -> Loaded {
        guard let id, id != BuiltInBuddy.id else {
            return Loaded(manifest: BuiltInBuddy.manifest, path: nil, isFallback: false)
        }
        let path = "\(Self.searchPath)/\(id).buddy"
        switch Self.read(path: path) {
        case let .success(manifest):
            return Loaded(manifest: manifest, path: path, isFallback: false)
        case let .failure(error):
            problems.append("« \(id) » : \(error)")
            return Loaded(manifest: BuiltInBuddy.manifest, path: nil, isFallback: true)
        }
    }

    /// Every buddy that parses, for a picker.
    public static func available() -> [BuddyManifest] {
        var found = [BuiltInBuddy.manifest]
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: searchPath)
        else { return found }
        for entry in entries.sorted() {
            guard entry.hasSuffix(".buddy") else { continue }
            if case let .success(manifest) = read(path: "\(searchPath)/\(entry)") {
                found.append(manifest)
            }
        }
        return found
    }

    /// Read and validate one buddy file. Errors are values, never traps.
    public static func read(path: String) -> Result<BuddyManifest, LoadError> {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { return .failure(.notFound) }

        let id = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".buddy", with: "")
        let result = BuddyFile.parse(text, id: id, name: id.capitalized)
        guard let manifest = result.manifest else {
            return .failure(.invalidJSON(result.problems.joined(separator: " · ")))
        }
        do {
            try manifest.validate()
            return .success(manifest)
        } catch let error as BuddyManifest.ValidationError {
            return .failure(.invalid(error))
        } catch {
            return .failure(.invalidJSON(error.localizedDescription))
        }
    }
}

/// The buddy that ships in the binary.
///
/// Written as a manifest rather than as a special case, so the format is
/// exercised by the default path on every launch. A format only used by
/// third parties is a format that breaks quietly.
public enum BuiltInBuddy {
    public static let id = "orb"

    /// The built-in buddy, written in the same `.buddy` text format as any
    /// other — so the format is exercised by the default path on every launch.
    /// A format only third parties use is a format that breaks quietly.
    public static let text = """
    # VibeBuddy — buddy par défaut
    # une image par ligne, une seconde par image

    sleeping (blue #00BBFF)
    ( -.- )
    ( -.- ) z
    ( -.- ) zz

    idle (yellow #FFBB00)
    ( ^.^ )
    ( -.- )
    ( ^.^ )
    ( ^.- )

    working (green #55FF55)
    ( o.o )
    ( O.o )
    ( o.O )
    ( O.O )

    awaiting (blue #00BBFF)
    ( ?.? )
    ( ?.. )
    ( ..? )

    finished (blue #00BBFF)
    ( ^.^ ) *
    ( ^o^ ) +
    ( ^.^ ) *

    failed (red #FF5555)
    ( x.x )
    ( >.< )
    ( x.x )
    """

    public static let manifest: BuddyManifest = {
        // Parsing cannot fail: the text is a literal in this file and covered by
        // a test. If it ever does, an empty face beats a launch crash.
        BuddyFile.parse(text, id: id, name: "Orb").manifest ?? BuddyManifest.empty
    }()
}

extension BuddyManifest {
    /// Last resort: renders nothing, crashes nowhere.
    static let empty = BuddyManifest(
        schema: supportedSchema, kind: .ascii, id: "empty", name: "—",
        colour: "#FFFFFF", fontSize: 12,
        framesPerSecond: BuddyManifest.defaultFrameRate, font: nil,
        expressions: ["idle": Expression(frames: ["( . )"], motion: .none, colour: nil)]
    )
}
