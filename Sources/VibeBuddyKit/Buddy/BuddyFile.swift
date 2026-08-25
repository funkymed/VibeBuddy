import CoreGraphics
import Foundation

/// Parser for the `.buddy` text format. face: 80x30 oval
public struct BuddyFile: Sendable {
    public struct ParseResult: Sendable {
        public let manifest: BuddyManifest?
        /// Unparsed lines, with their number, so an editor can point at them.
        public let problems: [String]
    }

    /// `name (anything #RRGGBB)` — the colour word is decoration.
    private static func headerPattern()
        -> Regex<(Substring, Substring, Substring, Substring)> {
        /^\s*([a-zA-Z][a-zA-Z0-9_-]*)\s*\(([^)]*?)#([0-9A-Fa-f]{6})\s*\)\s*$/
    }

    public static func parse(_ text: String, id: String, name: String) -> ParseResult {
        var expressions: [String: BuddyManifest.Expression] = [:]
        var problems: [String] = []

        let header = headerPattern()
        var current: (name: String, colour: String)?
        var eye: EyeSpec?
        var face = BuddyManifest.FacePlate()

        func flush() {
            guard let section = current else { return }
            defer { current = nil; eye = nil }
            guard let spec = eye else {
                problems.append("« \(section.name) » ne décrit aucun visage")
                return
            }
            expressions[section.name] = BuddyManifest.Expression(
                eye: spec,
                motion: MotionKind.default(for: section.name),
                colour: "#" + section.colour)
        }

        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("#") && (try? header.wholeMatch(in: line)) == nil {
                continue  // a comment, not a colour
            }

            // Directives only before the first section, so a pose line that reads like
            // one is never eaten.
            if current == nil, let colon = trimmed.firstIndex(of: ":") {
                let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = trimmed[trimmed.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                if key == "face" {
                    if let parsed = parseFace(value) { face = parsed }
                    else {
                        problems.append(
                            "ligne \(index + 1) : « face: \(value) » illisible, attendu « 80x30 oval »")
                    }
                    continue
                }
                // `kind`, `font`, `size` and `speed` belonged to the glyph format and
                // are gone.
                if ["kind", "font", "size", "speed"].contains(key) {
                    problems.append("ligne \(index + 1) : « \(key): » n'existe plus")
                    continue
                }
            }

            if let match = try? header.wholeMatch(in: line) {
                flush()
                current = (String(match.1).lowercased(), String(match.3).uppercased())
                continue
            }

            guard current != nil else {
                problems.append("ligne \(index + 1) hors section : « \(trimmed) »")
                continue
            }
            // Several lines merge into one spec, so a face can be split across lines
            // the way a long one wants to be.
            switch applyPose(trimmed, to: eye ?? EyeSpec(pose: EyePose())) {
            case let .ok(updated): eye = updated
            case let .unknown(token):
                problems.append("ligne \(index + 1) : clé « \(token) » inconnue")
            }
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
                id: id,
                name: name,
                colour: expressions["idle"]?.colour ?? "#FFFFFF",
                face: face,
                expressions: expressions
            ),
            problems: problems
        )
    }

    /// `80x30 oval` or `58x28 r10` — width, height, then either the word `oval` or a
    /// corner radius.
    static func parseFace(_ text: String) -> BuddyManifest.FacePlate? {
        let pattern = /^(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)(?:\s+(oval|r\s*\d+(?:\.\d+)?))?$/
        guard let match = try? pattern.wholeMatch(
                in: text.trimmingCharacters(in: .whitespaces).lowercased()),
              let width = Double(String(match.1)), let height = Double(String(match.2))
        else { return nil }
        let tail = match.3.map(String.init)
        if tail == "oval" {
            return BuddyManifest.FacePlate(
                width: CGFloat(width), height: CGFloat(height),
                radius: CGFloat(height / 2), silhouette: .oval)
        }
        let radius = tail
            .map { $0.dropFirst().trimmingCharacters(in: .whitespaces) }
            .flatMap { Double($0) } ?? (height / 3)
        return BuddyManifest.FacePlate(
            width: CGFloat(width), height: CGFloat(height),
            radius: CGFloat(radius), silhouette: .rounded)
    }

    /// One line of a section.
    static func applyPose(_ line: String, to spec: EyeSpec) -> PoseOutcome {
        var spec = spec
        var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let head = tokens.first else { return .ok(spec) }
        let target: Target
        switch head.lowercased() {
        case "eye":   target = .eye
        case "mouth": target = .mouth
        case "time":  target = .time
        default:      return .unknown(head)
        }
        tokens.removeFirst()

        // A `mouth` line is what creates the mouth: a face with no such line has no
        // mouth at all, rather than one of size zero.
        if target == .mouth, spec.pose.mouth == nil {
            spec.pose.mouth = FaceFeature(shape: .arc, width: 18, height: 7, offsetY: 7)
        }

        for token in tokens {
            guard let colon = token.firstIndex(of: ":") else { return .unknown(token) }
            let key = token[..<colon].lowercased()
            let raw = String(token[token.index(after: colon)...])

            if key == "shape" {
                guard let shape = EyeShape(rawValue: raw.lowercased()) else { return .unknown(raw) }
                switch target {
                case .eye:   spec.pose.eye.shape = shape
                case .mouth: spec.pose.mouth?.shape = shape
                case .time:  return .unknown(key)
                }
                continue
            }
            if key == "gaze" {
                guard target == .time,
                      let kind = GazeKind(rawValue: raw.lowercased()) else { return .unknown(raw) }
                spec.gaze = kind
                continue
            }
            guard let value = Double(raw) else { return .unknown(token) }
            let number = CGFloat(value)

            if target == .time {
                switch key {
                case "beat":
                    spec.beat = min(EyeSpec.maximumBeat, max(EyeSpec.minimumBeat, value))
                // Zero is the only way to say "never blinks", so it is not rejected.
                case "blink":  spec.blink = max(0, min(1, value))
                case "depth":  spec.depthScale = max(0, min(4, number))
                case "grain":  spec.grain = max(0, min(1, value))
                case "glitch": spec.glitch = max(0, min(1, value))
                default:       return .unknown(key)
                }
                continue
            }

            var feature = target == .eye ? spec.pose.eye : (spec.pose.mouth ?? FaceFeature())
            switch key {
            case "w":    feature.width = number
            case "h":    feature.height = number
            case "r":    feature.radius = number
            case "t":    feature.thickness = number
            case "bend": feature.bend = number
            case "tilt": feature.tilt = number
            case "y":    feature.offsetY = number
            case "gap":
                guard target == .eye else { return .unknown(key) }
                spec.pose.gap = number
            default: return .unknown(key)
            }
            if target == .eye { spec.pose.eye = feature } else { spec.pose.mouth = feature }
        }
        return .ok(spec)
    }

    enum Target { case eye, mouth, time }

    /// Not `Result`: `String` is not an `Error`, and wrapping the key in one would be
    /// ceremony around a parser that never throws by design.
    enum PoseOutcome {
        case ok(EyeSpec)
        case unknown(String)
    }
}

extension MotionKind {
    /// A face moves in beats, so the only motion left for the screen is a reaction — one
    /// that happens and settles.
    static func `default`(for expression: String) -> MotionKind {
        switch expression {
        case "finished": return .bounce
        case "failed":   return .shake
        default:         return .none
        }
    }
}
