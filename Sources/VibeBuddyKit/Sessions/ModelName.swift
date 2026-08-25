import Foundation

/// The version has to survive: `opus` alone cannot tell Opus 4.8 from Opus 5.
public enum ModelName {
    static func isDateStamp(_ component: Substring) -> Bool {
        component.count == 8 && component.allSatisfy(\.isNumber)
    }

    /// Unknown shapes come back unchanged: showing it raw beats a confident half of it.
    public static func short(_ model: String) -> String {
        guard !model.isEmpty else { return "" }
        var text = model
        // A `[1m]` suffix is a configuration, not a model; the panel gauges the window.
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
