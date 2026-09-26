import SwiftUI

/// ✓ ✗ ? — what the tongue under the notch says, drawn like the eyes: whole cells,
/// the same gradient, the same glow. Kept apart from `EyeShape` on purpose: these are
/// not eyes, and a `.buddy` must not be able to pick them as such.
///
/// Bitmaps rather than contours. At six cells tall an analytic stroke is decided by
/// which side of a cell centre it happens to fall, and the tick came out as a smudge;
/// a bitmap is the glyph a person would draw on that grid. What is shared with the
/// eyes is the rendering, which is what makes them read as one screen.
public enum AlertGlyph: String, Sendable, CaseIterable {
    case check, cross, question

    public init(_ kind: SessionAlert.Kind) {
        switch kind {
        case .finished: self = .check
        case .failed: self = .cross
        case .needsAttention: self = .question
        }
    }

    /// The face whose colour the glyph wears.
    public var expression: BuddyExpression {
        switch self {
        case .check: return .finished
        case .cross: return .failed
        case .question: return .awaiting
        }
    }

    /// Rows top to bottom, `#` lit.
    public var bitmap: [String] {
        switch self {
        case .check:
            return ["......#",
                    ".....##",
                    "#...##.",
                    "##.##..",
                    ".###...",
                    "..#...."]
        case .cross:
            return ["##..##",
                    ".####.",
                    "..##..",
                    "..##..",
                    ".####.",
                    "##..##"]
        case .question:
            return [".####.",
                    "##..##",
                    "...##.",
                    "..##..",
                    "......",
                    "..##.."]
        }
    }

    public var columns: Int { bitmap.map(\.count).max() ?? 0 }
    public var rows: Int { bitmap.count }

    /// The lit cells at `pitch`, origin top left.
    public func cells(pitch: CGFloat) -> [CGRect] {
        var out: [CGRect] = []
        for (row, line) in bitmap.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                out.append(CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch,
                                  width: pitch, height: pitch))
            }
        }
        return out
    }

    public func size(pitch: CGFloat) -> CGSize {
        CGSize(width: CGFloat(columns) * pitch, height: CGFloat(rows) * pitch)
    }
}

/// One glyph, rendered as the eyes render their features.
public struct AlertGlyphView: View {
    let glyph: AlertGlyph
    let colour: Color
    var pitch: CGFloat = BuddyView.pixelSize

    public init(glyph: AlertGlyph, colour: Color, pitch: CGFloat = BuddyView.pixelSize) {
        self.glyph = glyph
        self.colour = colour
        self.pitch = pitch
    }

    public var body: some View {
        // Same three steps as `EyesFaceView.features`: brighter at the top, one glow.
        CellsShape(cells: glyph.cells(pitch: pitch), pitch: pitch)
            .fill(LinearGradient(colors: [colour, colour.opacity(0.72)],
                                 startPoint: .top, endPoint: .bottom))
            .shadow(color: colour.opacity(0.55), radius: 2)
            .frame(width: glyph.size(pitch: pitch).width,
                   height: glyph.size(pitch: pitch).height)
            .allowsHitTesting(false)
    }
}

public extension BuddyManifest {
    /// The colour a face wears for `expression`, else the buddy's own.
    func colour(for expression: BuddyExpression) -> Color {
        Color(hex: self.expression(expression)?.colour ?? colour) ?? .primary
    }
}
