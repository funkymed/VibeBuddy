import AppKit
import CoreGraphics

/// Where things sit in the collapsed pill: content, the hardware cutout, content.
public struct PillLayout: Sendable, Equatable {
    public static let slotPadding: CGFloat = 6

    /// Inset on the outer edge of the counter's ear.
    public static let counterPadding: CGFloat = 10

    /// Radius of the pill's bottom corners.
    public static let pillCornerRadius: CGFloat = 12

    /// The smallest inset that keeps the face clear of that arc — and nothing more.
    public static func cornerClearance(pillHeight: CGFloat, buddyHeight: CGFloat) -> CGFloat {
        let r = pillCornerRadius
        let y = max(0, (pillHeight - buddyHeight) / 2)   // air below the face
        guard y < r else { return 0 }                    // the face clears the arc entirely
        return r - sqrt(max(0, r * r - (r - y) * (r - y)))
    }

    public static let emptySlotWidth: CGFloat = 18

    /// Widest a *face* may be. 96 pt clears the widest measured on the shipped buddies;
    /// past it the buddy is scaled down (`BuddyView`, `fit:`).
    public static let maxSlotWidth: CGFloat = 96

    /// Air above and below the buddy in the collapsed pill. Only ever a floor to shrink
    /// against: in the bar the buddy is drawn at the size its manifest declares — 100 %,
    /// judged by eye on 2026-08-21 as the one that reads best.
    public static let buddyVerticalInset: CGFloat = 1

    public let leftWidth: CGFloat
    public let rightWidth: CGFloat
    public let notchWidth: CGFloat
    public let height: CGFloat
    /// The size the buddy's face is drawn at inside the collapsed pill — as tall as the
    /// bar, less `buddyVerticalInset`.
    public let buddyBox: CGSize
    /// What is left around the widest thing an ear holds.
    public let slotInset: CGFloat

    public var totalWidth: CGFloat { leftWidth + notchWidth + rightWidth }

    public var notchAlignmentOffset: CGFloat { (rightWidth - leftWidth) / 2 }

    public init(
        leftWidth: CGFloat, rightWidth: CGFloat, notchWidth: CGFloat, height: CGFloat,
        buddyBox: CGSize = .zero,
        slotInset: CGFloat = PillLayout.slotPadding
    ) {
        self.leftWidth = leftWidth
        self.rightWidth = rightWidth
        self.notchWidth = notchWidth
        self.height = height
        self.buddyBox = buddyBox
        self.slotInset = slotInset
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
        let height = notch?.height ?? NotchFrameSolver.floatingPillHeight

        // How big the face is actually drawn: the size its manifest declares, and
        // smaller only when the bar cannot hold it.
        var box = buddy.map { manifest -> CGSize in
            let plate = manifest.face
            guard plate.width > 0, plate.height > 0 else { return .zero }
            let k = min(1, max(0, (height - buddyVerticalInset * 2) / plate.height))
            return CGSize(width: plate.width * k, height: plate.height * k)
        } ?? .zero

        // The ear is as narrow as the buddy allows: its width plus the arc's clearance,
        // and nothing else.
        let clearance = cornerClearance(pillHeight: height, buddyHeight: box.height)
        let left = box.width > 0 ? box.width + clearance * 2 : emptySlotWidth

        // An alert takes the right ear over from the counter, never stacks.
        let rightText = alertText ?? (sessionCount > 0 ? counterText(sessionCount) : nil)
        let right = rightText.map {
            measure($0, size: counterFontSize, weight: .semibold) + slotPadding * 2
        } ?? emptySlotWidth

        let natural = max(left, right, emptySlotWidth)

        let slot = min(max(natural, emptySlotWidth), maxSlotWidth)

        // A hand-edited manifest can be wider than any ear we will draw.
        let room = slot - clearance * 2
        if box.width > room, box.width > 0 {
            let k = room / box.width
            box = CGSize(width: room, height: box.height * k)
        }

        return PillLayout(
            leftWidth: slot,
            rightWidth: slot,
            // Without a cutout there is no hole to straddle: a token gap.
            notchWidth: notch?.width ?? 24,
            height: height,
            buddyBox: box,
            // What is left around the widest thing an ear holds.
            slotInset: max(slotPadding, (slot - max(0, natural - slotPadding * 2)) / 2)
        )
    }

    public static func counterText(_ count: Int) -> String { "×\(count)" }

    /// Measured widths, keyed by everything that changes one.
    @MainActor private static var widths: [Key: CGFloat] = [:]
    @MainActor private static var fonts: [Key: NSFont] = [:]

    struct Key: Hashable {
        let text: String
        let size: CGFloat
        let weight: CGFloat
        let family: String?
    }

    static let cacheLimit = 512

    @MainActor
    public static func measure(
        _ text: String, size: CGFloat, weight: NSFont.Weight, family: String? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = Key(text: text, size: size, weight: weight.rawValue, family: family)
        if let cached = widths[key] { return cached }

        // Measure in the font that will actually draw it: measuring in one family and
        // rendering in another is how a slot ends up clipped.
        let attributed = NSAttributedString(
            string: text, attributes: [.font: font(size: size, weight: weight, family: family)])
        let width = ceil(attributed.size().width)
        if widths.count >= cacheLimit { widths.removeAll(keepingCapacity: true) }
        widths[key] = width
        return width
    }

    /// The font a measurement or a line height is taken in, cached: `NSFont` lookup by
    /// name is not free either.
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

