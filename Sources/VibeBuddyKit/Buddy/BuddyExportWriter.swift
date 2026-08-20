import Foundation

/// Flattens a manifest — file and override layer already merged — back into one
/// self-contained `.buddy`.
/// See RFC-005, "Notes d'implémentation".
public enum BuddyExportWriter {

    /// Keep the expression order the enum's, never the dictionary's: a
    /// dictionary has no order and two exports would differ by shuffling alone.
    public static func text(for manifest: BuddyManifest, name: String? = nil) -> String {
        var lines = [
            "# \(name ?? manifest.name) — exporté par \(AppName.display)",
            "# Un visage par section : l'œil est dessiné deux fois, en miroir.",
            "",
            "face: \(number(Double(manifest.face.width)))x\(number(Double(manifest.face.height))) "
                + (manifest.face.silhouette == .oval
                   ? "oval"
                   : "r\(number(Double(manifest.face.radius)))"),
            "",
        ]
        for expression in BuddyExpression.allCases {
            guard let settings = manifest.expressions[expression.rawValue] else { continue }
            lines.append("\(expression.rawValue) (colour \(settings.colour ?? manifest.colour))")
            lines.append(contentsOf: poseLines(settings.eye))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// `overwrite` is explicit: the obvious destination is the hand-written file.
    @discardableResult
    public static func write(
        _ manifest: BuddyManifest, to path: String, overwrite: Bool = false
    ) -> Result<String, WriteError> {
        if !overwrite, FileManager.default.fileExists(atPath: path) {
            return .failure(.exists)
        }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        do {
            try text(for: manifest).write(toFile: path, atomically: true, encoding: .utf8)
            return .success(path)
        } catch {
            return .failure(.io(error.localizedDescription))
        }
    }

    public enum WriteError: Error, Equatable, CustomStringConvertible {
        case exists
        case io(String)

        public var description: String {
            switch self {
            case .exists: return "un fichier porte déjà ce nom"
            case let .io(detail): return detail
            }
        }
    }

    /// The inverse of `BuddyFile.applyPose`. Every key is written, including
    /// the ones left at their default: an export is meant to be edited by hand,
    /// and a key that is absent is a key nobody discovers.
    public static func poseLines(_ eye: EyeSpec) -> [String] {
        var lines = ["eye " + keys(eye.pose.eye) + " gap:" + number(Double(eye.pose.gap))]
        if let mouth = eye.pose.mouth { lines.append("mouth " + keys(mouth)) }
        lines.append(
            "time beat:" + number(eye.beat)
                + " blink:" + number(eye.blink)
                + " depth:" + number(Double(eye.depthScale))
                + " grain:" + number(eye.grain)
                + " glitch:" + number(eye.glitch)
                + " gaze:" + eye.gaze.rawValue)
        return lines
    }

    /// One line, for the places that show a face in a single row (`--info`).
    public static func poseLine(_ eye: EyeSpec) -> String {
        poseLines(eye).joined(separator: " · ")
    }

    static func keys(_ feature: FaceFeature) -> String {
        var parts = ["shape:" + feature.shape.rawValue]
        parts.append("w:" + number(Double(feature.width)))
        parts.append("h:" + number(Double(feature.height)))
        parts.append("r:" + number(Double(feature.radius)))
        parts.append("t:" + number(Double(feature.thickness)))
        parts.append("bend:" + number(Double(feature.bend)))
        parts.append("tilt:" + number(Double(feature.tilt)))
        parts.append("y:" + number(Double(feature.offsetY)))
        return parts.joined(separator: " ")
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
