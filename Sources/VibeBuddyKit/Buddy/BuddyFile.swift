import Foundation

/// Parser for the `.buddy` text format: `name (colour #RRGGBB) [size] [speed]`
/// opens a section, one frame per line, a blank line closes it.
///
/// A `.buddy` is data outside the binary: recompiling changes nothing, the file
/// has to be re-read. Parsing never throws — a bad section is skipped.
/// See RFC-005, "Notes d'implémentation".
public struct BuddyFile: Sendable {

    public struct ParseResult: Sendable {
        public let manifest: BuddyManifest?
        /// Unparsed lines, with their number, so an editor can point at them.
        public let problems: [String]
    }

    /// `name (anything #RRGGBB) [size] [speed]` — the colour word is decoration.
    /// Do not hoist this into a stored property: `Regex` is not `Sendable`, and
    /// sharing one across concurrent parses is a real race.
    private static func headerPattern()
        -> Regex<(Substring, Substring, Substring, Substring, Substring?, Substring?)> {
        /^\s*([a-zA-Z][a-zA-Z0-9_-]*)\s*\(([^)]*?)#([0-9A-Fa-f]{6})\s*\)\s*(\d{1,2})?\s*(\d+(?:\.\d+)?)?\s*$/
    }

    public static func parse(_ text: String, id: String, name: String) -> ParseResult {
        var expressions: [String: BuddyManifest.Expression] = [:]
        var problems: [String] = []

        let header = headerPattern()
        var current: (name: String, colour: String, size: CGFloat?,
                      rate: Double?, frames: [String])?
        var font: String?
        var size: CGFloat = 13
        var speed: Double = BuddyManifest.defaultFrameRate

        func flush() {
            guard let section = current else { return }
            guard !section.frames.isEmpty else {
                problems.append("« \(section.name) » n'a aucune image")
                current = nil
                return
            }
            expressions[section.name] = BuddyManifest.Expression(
                frames: section.frames,
                motion: MotionKind.default(for: section.name),
                colour: "#" + section.colour,
                fontSize: section.size,
                framesPerSecond: section.rate
            )
            current = nil
        }

        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("#") && (try? header.wholeMatch(in: line)) == nil {
                continue  // a comment, not a colour
            }

            // Directives only before the first section, so a frame that reads
            // like one is never eaten.
            if current == nil, let colon = trimmed.firstIndex(of: ":") {
                let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = trimmed[trimmed.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                if key == "font", !value.isEmpty { font = value; continue }
                if key == "size", let parsed = Double(value), parsed >= 6, parsed <= 48 {
                    size = CGFloat(parsed); continue
                }
                // Out-of-range values are reported, never clamped.
                if key == "speed", let parsed = Double(value),
                   BuddyManifest.isValidFrameRate(parsed) {
                    speed = parsed; continue
                }
            }

            if let match = try? header.wholeMatch(in: line) {
                flush()
                let perExpressionSize: CGFloat? = match.4
                    .flatMap { Double(String($0)) }
                    .map { CGFloat($0) }
                let perExpressionRate: Double? = match.5
                    .flatMap { Double(String($0)) }
                    .flatMap { BuddyManifest.isValidFrameRate($0) ? $0 : nil }
                if match.5 != nil, perExpressionRate == nil {
                    problems.append(
                        "ligne \(index + 1) : vitesse hors bornes, celle du fichier est gardée")
                }
                current = (String(match.1).lowercased(), String(match.3).uppercased(),
                           perExpressionSize, perExpressionRate, [])
                continue
            }

            guard current != nil else {
                problems.append("ligne \(index + 1) hors section : « \(trimmed) »")
                continue
            }
            // Do not trim frames: several of these faces are drawn out of their
            // leading and trailing spaces.
            current?.frames.append(line)
        }
        flush()

        guard expressions["idle"] != nil else {
            return ParseResult(
                manifest: nil,
                problems: problems + ["l'expression « idle » est obligatoire"])
        }

        return ParseResult(
            manifest: BuddyManifest(
                schema: BuddyManifest.supportedSchema,
                kind: .ascii,
                id: id,
                name: name,
                colour: expressions["idle"]?.colour ?? "#FFFFFF",
                fontSize: size,
                framesPerSecond: speed,
                font: font,
                expressions: expressions
            ),
            problems: problems
        )
    }
}

extension MotionKind {
    static func `default`(for expression: String) -> MotionKind {
        switch expression {
        case "sleeping": return .none
        case "failed":   return .shake
        case "finished": return .bounce
        default:         return .none
        }
    }
}
