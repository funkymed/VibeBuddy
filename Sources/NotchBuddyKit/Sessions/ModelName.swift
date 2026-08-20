import Foundation

/// Turns `claude-opus-5` into `opus 5`.
///
/// # Why not just show the raw name
///
/// `claude-opus-5` is as wide as the project name and says less: the `claude-`
/// is true of every session this app will ever show, and a column that repeats
/// the same eight characters on every row is a column that stops being read.
///
/// # Why the version has to survive
///
/// The first version cut at the first dash and produced `opus` — which is the
/// one part that cannot distinguish two sessions. Running Opus 4.8 next to
/// Opus 5 is exactly when the model matters, and that is precisely the case it
/// erased. The family alone is decoration; the family plus the version is the
/// answer to "what is this session actually running".
public enum ModelName {

    /// A dated build id: `claude-haiku-4-5-20251001`. Dropped — it identifies a
    /// release, not a model, and nobody reads a row to learn a build date.
    static func isDateStamp(_ component: Substring) -> Bool {
        component.count == 8 && component.allSatisfy(\.isNumber)
    }

    /// Short label for a row.
    ///
    /// Unknown shapes come back unchanged rather than mangled: this is a
    /// cosmetic transform over a string another program writes, and the day it
    /// changes shape, showing it raw beats showing a confident half of it.
    public static func short(_ model: String) -> String {
        guard !model.isEmpty else { return "" }
        var text = model
        // A `[1m]` suffix selects the million-token window; it is a
        // configuration, not a model, and the panel shows the context window as
        // a gauge already.
        if let bracket = text.firstIndex(of: "[") { text = String(text[..<bracket]) }
        if text.hasPrefix("claude-") { text.removeFirst("claude-".count) }

        var parts = text.split(separator: "-")
        guard let family = parts.first else { return model }
        parts.removeFirst()
        parts.removeAll(where: isDateStamp)

        let version = parts.joined(separator: ".")
        return version.isEmpty ? String(family) : "\(family) \(version)"
    }
}
