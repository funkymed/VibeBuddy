import Foundation

/// Just enough diff to show what a write would do.
///
/// A hundred lines of LCS beats asking the user to trust a summary of a change
/// to their own file. Not a general-purpose tool: it prints whole lines, has no
/// options, and exists for one screen of output.
///
/// In the Kit rather than in the CLI that first needed it, because the consent
/// screen of RFC-007 T8 shows the same diff for the same reason — and the one
/// thing worse than asking someone to trust a summary is showing them two
/// summaries that disagree.
public enum TextDiff {

    public static func unified(_ old: String, _ new: String, context: Int = 3) -> String {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let edits = diff(a, b)

        // Which lines to print: every change, plus `context` lines either side.
        var interesting = Set<Int>()
        for (index, edit) in edits.enumerated() where edit.kind != .same {
            for offset in max(0, index - context)...min(edits.count - 1, index + context) {
                interesting.insert(offset)
            }
        }
        guard !interesting.isEmpty else { return "  (aucune différence)" }

        var out: [String] = []
        var skipping = false
        for (index, edit) in edits.enumerated() {
            guard interesting.contains(index) else {
                if !skipping { out.append("  …"); skipping = true }
                continue
            }
            skipping = false
            switch edit.kind {
            case .same:    out.append("   \(edit.text)")
            case .removed: out.append("  -\(edit.text)")
            case .added:   out.append("  +\(edit.text)")
            }
        }
        return out.joined(separator: "\n")
    }

    public struct Edit { enum Kind { case same, removed, added }; let kind: Kind; let text: String }

    /// Longest common subsequence, walked back into edits.
    public static func diff(_ a: [String], _ b: [String]) -> [Edit] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var out: [Edit] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                out.append(Edit(kind: .same, text: a[i])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                out.append(Edit(kind: .removed, text: a[i])); i += 1
            } else {
                out.append(Edit(kind: .added, text: b[j])); j += 1
            }
        }
        while i < a.count { out.append(Edit(kind: .removed, text: a[i])); i += 1 }
        while j < b.count { out.append(Edit(kind: .added, text: b[j])); j += 1 }
        return out
    }
}
