import Foundation

/// Parser for the `.buddy` text format.
///
/// # Why not JSON
///
/// A buddy is a handful of kaomoji. In JSON they arrive as `"\u{1D5D3}"` escapes
/// and unbalanced-looking quotes, and editing one means counting backslashes.
/// The format below is what someone writes when asked to describe a buddy on a
/// napkin — which is literally where it came from:
///
/// ```
/// sleeping (blue #00BBFF)
/// ᓚ₍⑅^- .-^₎ -ᶻ 𝗓 𐰁
/// ᓚ₍⑅^- .-^₎ -𐰁 ᶻ 𝗓
///
/// idle (yellow #FFBB00)
/// (ᵕ • ᴗ •)
/// („• ֊ •„)
/// ```
///
/// **One frame per line, one second per frame.** A blank line ends a section.
/// The colour name before the hex is ignored — it is there for the human.
///
/// Optional directives may open the file:
///
/// ```
/// font: Menlo
/// size: 14
/// speed: 2          # images par seconde ; 1 par défaut
/// ```
///
/// An expression may override the size, then the speed, on its own header line:
///
/// ```
/// working (green #55FF55) 17 4
/// ```
///
/// The two numbers are positional — size first, speed second — so an expression
/// that only wants a different speed still states its size. Named suffixes were
/// the alternative and they turn a napkin format into a small language; a header
/// with two numbers on it is still readable out loud.
///
/// A missing `font` means the system font, which is the right default: it
/// composes fallbacks per glyph, and no single installed family covers the rare
/// scripts these faces are built from.
///
/// Parsing never throws. A malformed section is skipped and reported, because a
/// buddy file is something a user edits by hand and half a buddy beats none.
public struct BuddyFile: Sendable {

    public struct ParseResult: Sendable {
        public let manifest: BuddyManifest?
        /// Lines that could not be understood, with their number, so an editor
        /// can be pointed at the actual problem.
        public let problems: [String]
    }

    /// `name (anything #RRGGBB)` — the colour word is decoration.
    ///
    /// Built per parse rather than held statically: `Regex` is not `Sendable`,
    /// and a shared one across concurrent parses is a real race rather than a
    /// compiler complaint. Parsing happens once per buddy file.
    private static func headerPattern()
        -> Regex<(Substring, Substring, Substring, Substring, Substring?, Substring?)> {
        // Optional trailing size, then optional speed:
        // `working (green #55FF55) 17 4`
        //
        // The speed accepts a decimal point because half a frame per second is
        // a real thing to ask for; the size does not, because a fractional
        // point size is not.
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

            // Directives are only recognised before the first section, so a
            // frame that happens to read like one is never eaten.
            if current == nil, let colon = trimmed.firstIndex(of: ":") {
                let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = trimmed[trimmed.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                if key == "font", !value.isEmpty { font = value; continue }
                if key == "size", let parsed = Double(value), parsed >= 6, parsed <= 48 {
                    size = CGFloat(parsed); continue
                }
                // Out-of-range values fall through to the "unparsed line"
                // report rather than being clamped: a file asking for 200
                // images per second is a mistake, and silently drawing 30 hides
                // it until someone wonders why the buddy ignores them.
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
            // Frames keep their leading and trailing spaces: several of these
            // faces are built out of them, and trimming would break the drawing.
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
    /// Movement for an expression that did not name one.
    ///
    /// These faces animate by changing frames, so the motion on top is
    /// deliberately restrained — a bouncing face that is also cycling frames
    /// reads as broken rather than lively.
    static func `default`(for expression: String) -> MotionKind {
        switch expression {
        case "sleeping": return .none
        case "failed":   return .shake
        case "finished": return .bounce
        default:         return .none
        }
    }
}
