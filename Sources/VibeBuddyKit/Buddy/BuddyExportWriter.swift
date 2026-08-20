import Foundation

/// Flattens a manifest — file and override layer already merged — back into one
/// self-contained `.buddy`.
/// See RFC-005, "Notes d'implémentation".
public enum BuddyExportWriter {

    /// Keep the expression order the enum's, never the dictionary's: a
    /// dictionary has no order and two exports would differ by shuffling alone.
    public static func text(for manifest: BuddyManifest, name: String? = nil) -> String {
        var lines: [String] = [
            "# \(name ?? manifest.name) — exporté par \(AppName.display)",
            "# Une image par ligne. « speed » donne le nombre d'images par seconde.",
            "# Sur l'en-tête d'une expression : taille d'abord, vitesse ensuite.",
            "",
        ]
        if let font = manifest.font { lines.append("font: \(font)") }
        lines.append("size: \(number(Double(manifest.fontSize)))")
        lines.append("speed: \(number(manifest.framesPerSecond))")
        lines.append("")

        for expression in BuddyExpression.allCases {
            guard let settings = manifest.expressions[expression.rawValue] else { continue }
            let colour = settings.colour ?? manifest.colour
            var header = "\(expression.rawValue) (colour \(colour))"
            let size = settings.fontSize.map { number(Double($0)) }
            let rate = settings.framesPerSecond.map { number($0) }
            // Positional: the parser reads the first number as the size, so a
            // speed override forces its size to be written too.
            if let size { header += " \(size)" }
            else if rate != nil { header += " \(number(Double(manifest.fontSize)))" }
            if let rate { header += " \(rate)" }
            lines.append(header)
            lines.append(contentsOf: settings.frames)
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

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
