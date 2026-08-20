import Foundation

/// Flattens a manifest back into a `.buddy` file.
///
/// This is the counterweight to storing edits in preferences. Without it an
/// edited buddy could never leave the machine it was edited on, which would
/// close the "a buddy is data, and a company can ship its own" direction by
/// accident rather than by decision.
///
/// What it writes is the file the editor *would* have written: layer and file
/// already merged, nothing left to reconcile.
public enum BuddyExportWriter {

    /// The format, written back out.
    ///
    /// Expressions come out in a fixed order — the enum's, not the dictionary's.
    /// A dictionary has no order, and exporting the same buddy twice would
    /// otherwise produce two files that differ only by shuffling, which makes
    /// any diff useless.
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
            // Positional, so a speed override forces its size to be written too
            // — the parser reads the first number as the size.
            if let size { header += " \(size)" }
            else if rate != nil { header += " \(number(Double(manifest.fontSize)))" }
            if let rate { header += " \(rate)" }
            lines.append(header)
            lines.append(contentsOf: settings.frames)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Write it, atomically, and never on top of something unseen.
    ///
    /// `overwrite` is explicit because the obvious destination for an export is
    /// the file the buddy came from — and silently replacing a hand-written
    /// file is exactly what the preference layer exists to avoid.
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

    /// `15` rather than `15.0`, `0.5` unchanged — the format accepts both, and
    /// a file full of `.0` reads as machine output nobody should touch.
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
