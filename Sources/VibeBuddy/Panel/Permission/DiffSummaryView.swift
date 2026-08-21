import SwiftUI
import VibeBuddyKit

/// A file changing: the old side in red, the new in green.
///
/// Also draws a whole-file write, which reaches here as a diff with an empty
/// `before` — one code path, because a creation is a change with nothing on the
/// left.
// RFC-007 T5 — red/green rendering, visual taken from
// `NotchContentView.swift:1885-1930`, code extracted into this view.
struct DiffSummaryView: View {
    let path: String
    let before: String
    let after: String
    let l10n: Strings

    /// Tall enough to read a hunk, short enough to keep the decision bar on
    /// screen. The two sides were already cut to `diffLimit` at parse time, so
    /// the block below is bounded whatever the file weighs.
    private static let maxHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            head
            if lines.isEmpty { emptyNote } else { diffBlock }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Head

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Truncated from the head: the tail names the file.
            Text(path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(PanelInk.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 8)
            tally
        }
    }

    /// `nouveau fichier` when there is no left side, otherwise `−3 +12`.
    ///
    /// The counts stay as signs and digits rather than words: they mean the same
    /// in both languages, and they are the one part of this view a user reads
    /// before deciding.
    @ViewBuilder
    private var tally: some View {
        if removed.isEmpty && !added.isEmpty {
            Text(l10n.permissionNewFile)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PermissionInk.added)
                .fixedSize()
        } else {
            HStack(spacing: 6) {
                if !removed.isEmpty {
                    Text("−\(removed.count)")
                        .foregroundStyle(PermissionInk.removed)
                }
                if !added.isEmpty {
                    Text("+\(added.count)")
                        .foregroundStyle(PermissionInk.added)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .fixedSize()
        }
    }

    /// A `Write` of an empty file, or an edit whose two sides both came back
    /// blank. Saying so beats an empty box the user reads as a rendering bug.
    private var emptyNote: some View {
        Text(l10n.permissionNoContent)
            .font(.system(size: 12))
            .foregroundStyle(PanelInk.tertiary)
    }

    // MARK: - Body

    private var diffBlock: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    row(line)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .permissionBlock(maxHeight: Self.maxHeight)
    }

    private func row(_ line: Line) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.kind.sign)
                .foregroundStyle(ink(line.kind))
                .frame(width: 8, alignment: .leading)
            Text(line.text)
                .foregroundStyle(ink(line.kind))
                // Selectable so a line too long to read here can be pasted
                // somewhere it can be.
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .background(wash(line.kind))
    }

    private func wash(_ kind: Line.Kind) -> Color {
        kind == .note ? .clear : PermissionInk.wash(ink(kind))
    }

    private func ink(_ kind: Line.Kind) -> Color {
        switch kind {
        case .removed: return PermissionInk.removed
        case .added:   return PermissionInk.added
        case .note:    return PanelInk.tertiary
        }
    }

    // MARK: - Lines

    private struct Line: Identifiable {
        enum Kind: Equatable {
            case removed, added, note

            var sign: String {
                switch self {
                case .removed: return "−"
                case .added:   return "+"
                case .note:    return ""
                }
            }
        }

        let id: Int
        let kind: Kind
        let text: String
    }

    private var removed: [String] { Self.split(before) }
    private var added: [String] { Self.split(after) }

    private var lines: [Line] {
        var out: [Line] = []
        for text in removed { out.append(Line(id: out.count, kind: kind(of: text, fallback: .removed), text: text)) }
        for text in added { out.append(Line(id: out.count, kind: kind(of: text, fallback: .added), text: text)) }
        return out
    }

    /// The truncation marker the model appended is not part of the file, so it
    /// is not part of the change: neutral ink, no sign in the gutter. Drawing it
    /// green would claim Claude is about to write the marker into the file.
    ///
    /// The mark comes from `PermissionRequestModel` rather than being spelled out
    /// again here — two copies of the same literal in two modules is one edit
    /// away from a marker painted as an added line.
    private func kind(of text: String, fallback: Line.Kind) -> Line.Kind {
        text.hasPrefix(PermissionRequestModel.truncationMark) ? .note : fallback
    }

    /// Drops a single trailing empty line: a file that ends with a newline
    /// otherwise shows one blank tinted row that stands for nothing.
    private static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var parts = text.components(separatedBy: "\n")
        if parts.count > 1, parts.last?.isEmpty == true { parts.removeLast() }
        return parts
    }
}
