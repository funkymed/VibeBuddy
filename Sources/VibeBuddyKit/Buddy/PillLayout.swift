import AppKit
import CoreGraphics

/// Where things sit in the collapsed pill: content, the hardware cutout,
/// content. The middle slot is a hole — anything drawn there is invisible.
/// See RFC-005, "Notes d'implémentation".
public struct PillLayout: Sendable, Equatable {

    public static let slotPadding: CGFloat = 6

    /// Inset on the outer edge of an ear. Take it from `slotPadding`, never add
    /// to it: the measured slot width already includes both sides.
    public static let outerPadding: CGFloat = 6

    public static let emptySlotWidth: CGFloat = 18

    /// Widest an ear may get. 96 pt clears the widest face measured on the
    /// shipped buddies; past it the buddy is scaled down (`BuddyView`, `fit:`).
    public static let maxSlotWidth: CGFloat = 96

    public let leftWidth: CGFloat
    public let rightWidth: CGFloat
    public let notchWidth: CGFloat
    public let height: CGFloat

    public var totalWidth: CGFloat { leftWidth + notchWidth + rightWidth }

    public var notchAlignmentOffset: CGFloat { (rightWidth - leftWidth) / 2 }

    public init(leftWidth: CGFloat, rightWidth: CGFloat, notchWidth: CGFloat, height: CGFloat) {
        self.leftWidth = leftWidth
        self.rightWidth = rightWidth
        self.notchWidth = notchWidth
        self.height = height
    }

    @MainActor
    public static func resolve(
        geometry: NotchGeometry,
        buddy: BuddyManifest?,
        sessionCount: Int,
        alertText: String? = nil,
        counterFontSize: CGFloat = 11
    ) -> PillLayout {
        let notch = geometry.notchSize
        // Measure across *every* expression, each at its own point size: sizing
        // to the frame on screen resizes the pill every second.
        let left = buddy.map { manifest in
            let widest = manifest.candidateFrames
                .map { measure($0.text, size: $0.size, weight: .medium, family: manifest.font) }
                .max() ?? 0
            return widest + slotPadding * 2
        } ?? emptySlotWidth

        // An alert takes the right ear over from the counter, never stacks.
        let rightText = alertText ?? (sessionCount > 0 ? counterText(sessionCount) : nil)
        let right = rightText.map {
            measure($0, size: counterFontSize, weight: .semibold) + slotPadding * 2
        } ?? emptySlotWidth

        let slot = min(max(left, right, emptySlotWidth), maxSlotWidth)

        return PillLayout(
            leftWidth: slot,
            rightWidth: slot,
            // Without a cutout there is no hole to straddle: a token gap.
            notchWidth: notch?.width ?? 24,
            height: notch?.height ?? NotchFrameSolver.floatingPillHeight
        )
    }

    public static func counterText(_ count: Int) -> String { "×\(count)" }

    public func contentBox(vertical inset: CGFloat = 4) -> CGSize {
        CGSize(
            width: max(0, leftWidth - PillLayout.slotPadding * 2),
            height: max(0, height - inset * 2))
    }

    @MainActor
    public static func lineHeight(size: CGFloat, family: String?) -> CGFloat {
        let resolved = font(size: size, weight: .medium, family: family)
        return ceil(resolved.ascender - resolved.descender + resolved.leading)
    }

    /// Measured widths, keyed by everything that changes one.
    ///
    /// `BuddyView` measures inside a `TimelineView` body: at the `lively` tier
    /// that was ~360 `NSAttributedString` allocations per second while the
    /// panel was open, for values that never depend on time.
    @MainActor private static var widths: [Key: CGFloat] = [:]
    @MainActor private static var fonts: [Key: NSFont] = [:]

    struct Key: Hashable {
        let text: String
        let size: CGFloat
        let weight: CGFloat
        let family: String?
    }

    /// Cache ceiling. The buddy editor re-measures on every keystroke, so an
    /// unbounded cache grows for as long as someone is typing.
    static let cacheLimit = 512

    @MainActor
    public static func measure(
        _ text: String, size: CGFloat, weight: NSFont.Weight, family: String? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = Key(text: text, size: size, weight: weight.rawValue, family: family)
        if let cached = widths[key] { return cached }

        // Measure in the font that will actually draw it: measuring in one
        // family and rendering in another is how a slot ends up clipped.
        let attributed = NSAttributedString(
            string: text, attributes: [.font: font(size: size, weight: weight, family: family)])
        let width = ceil(attributed.size().width)
        if widths.count >= cacheLimit { widths.removeAll(keepingCapacity: true) }
        widths[key] = width
        return width
    }

    /// The font a measurement or a line height is taken in, cached: `NSFont`
    /// lookup by name is not free either.
    @MainActor
    static func font(size: CGFloat, weight: NSFont.Weight, family: String?) -> NSFont {
        let key = Key(text: "", size: size, weight: weight.rawValue, family: family)
        if let cached = fonts[key] { return cached }
        let resolved = family.flatMap { NSFont(name: $0, size: size) }
            ?? NSFont.systemFont(ofSize: size, weight: weight)
        if fonts.count >= cacheLimit { fonts.removeAll(keepingCapacity: true) }
        fonts[key] = resolved
        return resolved
    }
}
