import Testing
import CoreGraphics
@testable import VibeBuddyKit

private let notched = NotchGeometry(
    screenID: 1,
    screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    notchSize: CGSize(width: 220, height: 38)
)
private let plain = NotchGeometry(
    screenID: 2,
    screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    notchSize: nil
)

@Suite("Pill layout")
@MainActor
struct PillLayoutTests {
    @Test("the pill always overhangs the cutout on both sides")
    func overhangsNotch() {
        let layout = PillLayout.resolve(geometry: notched, buddy: BuiltInBuddy.manifest, sessionCount: 2)
        #expect(layout.totalWidth > layout.notchWidth)
        #expect(layout.leftWidth >= PillLayout.emptySlotWidth)
        #expect(layout.rightWidth >= PillLayout.emptySlotWidth)
    }

    @Test("the pill matches the notch height so it reads as one shape")
    func matchesNotchHeight() {
        let layout = PillLayout.resolve(geometry: notched, buddy: BuiltInBuddy.manifest, sessionCount: 1)
        #expect(layout.height == 38)
    }

    // The rule that is easy to forget because it is invisible in the common case: the
    // pill and the notch are both centred, so equal ears align by accident and unequal
    // ones do not.
    @Test("equal ears need no shift")
    func symmetricNeedsNoOffset() {
        let layout = PillLayout(leftWidth: 60, rightWidth: 60, notchWidth: 220, height: 38)
        #expect(layout.notchAlignmentOffset == 0)
    }

    @Test("unequal ears shift by half the difference")
    func asymmetricShifts() {
        let layout = PillLayout(leftWidth: 40, rightWidth: 100, notchWidth: 220, height: 38)
        #expect(layout.notchAlignmentOffset == 30)
        // Check it actually lands: the middle slot's left edge must sit at
        // -notchWidth/2 once the shift is applied.
        let leftEdgeOfGap = -layout.totalWidth / 2 + layout.leftWidth + layout.notchAlignmentOffset
        #expect(abs(leftEdgeOfGap - (-layout.notchWidth / 2)) < 0.001)
    }

    // Hard-coded slot widths work until a buddy has a longer face or a manifest changes
    // its font size, at which point the content overflows a slot sized for something
    // else.
    @Test("a longer face widens its own ear")
    func longerFaceWidensSlot() {
        let short = PillLayout.measure("=^^=", size: 13, weight: .bold)
        let long = PillLayout.measure("=^^^^^^=", size: 13, weight: .bold)
        #expect(long > short)
    }

    @Test("a bigger font widens its own ear")
    func biggerFontWidensSlot() {
        let small = PillLayout.measure("=^^=", size: 10, weight: .bold)
        let big = PillLayout.measure("=^^=", size: 20, weight: .bold)
        #expect(big > small)
    }

    @Test("the counter widens as it reaches two digits")
    func counterGrows() {
        let one = PillLayout.resolve(geometry: notched, buddy: nil, sessionCount: 1)
        let twelve = PillLayout.resolve(geometry: notched, buddy: nil, sessionCount: 12)
        #expect(twelve.rightWidth > one.rightWidth)
    }

    @Test("no sessions leaves a minimum ear rather than collapsing onto the notch")
    func zeroSessionsKeepsShape() {
        let layout = PillLayout.resolve(geometry: notched, buddy: nil, sessionCount: 0)
        #expect(layout.rightWidth == PillLayout.emptySlotWidth)
    }

    // An alert and the counter say the same kind of thing; stacking them would make the
    // pill grow twice for one event.
    @Test("an alert takes the right ear over from the counter")
    func alertReplacesCounter() {
        let counter = PillLayout.resolve(geometry: notched, buddy: nil, sessionCount: 3)
        let alert = PillLayout.resolve(
            geometry: notched, buddy: nil, sessionCount: 3, alertText: "notch terminé")
        #expect(alert.rightWidth > counter.rightWidth)
    }

    // Asymmetric ears were geometrically fine — the pill was shifted so its hole still
    // landed on the cutout — and looked wrong: the notch is symmetric, so a shape
    // hanging further out on one side reads as misaligned.
    @Test("both ears are the same width, whatever they hold")
    func earsAreSymmetric() {
        let layout = PillLayout.resolve(
            geometry: notched, buddy: BuiltInBuddy.manifest, sessionCount: 12)
        #expect(layout.leftWidth == layout.rightWidth)
        // Which makes the correction unnecessary rather than merely correct.
        #expect(layout.notchAlignmentOffset == 0)
    }

    @Test("the wider side sets the width, the narrower one is padded up to it")
    func widerSideWins() {
        let bare = PillLayout.resolve(geometry: notched, buddy: nil, sessionCount: 0)
        #expect(bare.leftWidth == PillLayout.emptySlotWidth)

        let withBuddy = PillLayout.resolve(
            geometry: notched, buddy: BuiltInBuddy.manifest, sessionCount: 0)
        // The right ear is empty here, so it inherits the buddy's width.
        #expect(withBuddy.rightWidth == withBuddy.leftWidth)
        #expect(withBuddy.rightWidth > PillLayout.emptySlotWidth)
    }

    @Test("a display without a cutout still produces a usable pill")
    func plainScreen() {
        let layout = PillLayout.resolve(geometry: plain, buddy: BuiltInBuddy.manifest, sessionCount: 1)
        #expect(layout.totalWidth > 0)
        #expect(layout.height == NotchFrameSolver.floatingPillHeight)
    }

    // The pill scale is a margin, not a zoom. 100 %, judged by eye on 2026-08-21.
    @Test("in the bar the buddy is drawn at the size its manifest declares")
    func buddyIsDrawnAtFullSize() {
        let face = BuiltInBuddy.manifest.face
        let layout = PillLayout.resolve(
            geometry: notched, buddy: BuiltInBuddy.manifest, sessionCount: 1)
        #expect(layout.buddyBox == CGSize(width: face.width, height: face.height))
    }

    // The ear is meant to be no wider than the buddy needs, so this pins the margin to
    // the arc's geometry rather than to a taste.
    @Test("the ear is exactly as wide as the buddy plus the corner's clearance")
    func earIsMinimal() {
        let layout = PillLayout.resolve(
            geometry: notched, buddy: BuiltInBuddy.manifest, sessionCount: 0)
        let clearance = PillLayout.cornerClearance(
            pillHeight: layout.height, buddyHeight: layout.buddyBox.height)
        #expect(layout.leftWidth == layout.buddyBox.width + clearance * 2)
        // And that clearance is what the 12 pt arc actually asks for at that height,
        // not a rounded-up constant.
        #expect(abs(clearance - 3.0557) < 0.001)
    }

    @Test("a face that clears the arc entirely asks for no margin at all")
    func shortFaceNeedsNoClearance() {
        // 12 pt of air below a face in a 38 pt bar puts it past the radius.
        #expect(PillLayout.cornerClearance(pillHeight: 38, buddyHeight: 14) == 0)
    }

    @Test("a bar too short for the face shrinks it rather than cropping it")
    func shortBarShrinks() {
        let shallow = NotchGeometry(
            screenID: 3,
            screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            notchSize: CGSize(width: 220, height: 20))
        let face = BuiltInBuddy.manifest.face
        let layout = PillLayout.resolve(
            geometry: shallow, buddy: BuiltInBuddy.manifest, sessionCount: 1)
        #expect(layout.buddyBox.height == 18)
        #expect(abs(layout.buddyBox.width / layout.buddyBox.height
                    - face.width / face.height) < 0.001)
    }

    @Test("measuring an empty string costs nothing")
    func emptyMeasure() {
        #expect(PillLayout.measure("", size: 13, weight: .bold) == 0)
    }
}

/// A `.buddy` is hand-edited text, so a manifest can ask for anything.
@Suite("Oversized buddies")
@MainActor
struct OversizedBuddyTests {
    private func giant() -> BuddyManifest {
        // Parsed, not validated: `BuddyManifest.validate` refuses a screen this wide,
        // but only `BuddyLoader` validates.
        BuddyFile.parse("""
        face: 200x60 r10

        idle (x #FFFFFF)
        eye shape:oval w:60 h:40 r:20 gap:40
        """, id: "giant", name: "Giant").manifest!
    }

    @Test("an ear never grows past the cap, whatever the buddy asks")
    func slotIsCapped() {
        let layout = PillLayout.resolve(geometry: notched, buddy: giant(), sessionCount: 1)
        #expect(layout.leftWidth == PillLayout.maxSlotWidth)
        #expect(layout.rightWidth == PillLayout.maxSlotWidth)
    }

    @Test("an oversized buddy is shrunk into the ear rather than clipped by it")
    func giantIsFittedToTheEar() {
        let layout = PillLayout.resolve(geometry: notched, buddy: giant(), sessionCount: 1)
        let box = layout.buddyBox
        let clearance = PillLayout.cornerClearance(
            pillHeight: layout.height, buddyHeight: box.height)
        #expect(box.width <= layout.leftWidth - clearance * 2)
        #expect(box.height < layout.height)
        #expect(box.height > 0)
        // Still the manifest's proportions, shrunk.
        let face = giant().face
        #expect(abs(box.width / box.height - face.width / face.height) < 0.001)
    }

    @Test("the shipped buddies are unaffected by the cap")
    func shippedBuddiesFit() {
        let layout = PillLayout.resolve(
            geometry: notched, buddy: BuiltInBuddy.manifest, sessionCount: 2)
        #expect(layout.leftWidth < PillLayout.maxSlotWidth)
    }
}

/// A round eye four cells across is not a circle.
@Suite("Corners the grid can draw")
struct DrawableRadiusTests {
    @Test("a radius the grid cannot express is rounded down to whole cells")
    func roundsToWholeCells() {
        // 6 pt of radius on a 3 pt grid is two cells, but one cell of straight edge has
        // to survive on each side.
        #expect(EyeRaster.drawableRadius(6, halfWidth: 6.5, halfHeight: 6, pitch: 3) == 3)
    }

    @Test("below one cell there is no corner left, and the eye is a square")
    func tinyEyesAreSquare() {
        #expect(EyeRaster.drawableRadius(6, halfWidth: 4, halfHeight: 3, pitch: 3) == 0)
        #expect(EyeRaster.drawableRadius(2, halfWidth: 20, halfHeight: 20, pitch: 3) == 0)
    }

    @Test("a face with cells to spare keeps the radius its author asked for")
    func generousGridsKeepTheRadius() {
        // The same eye at a 1 pt pitch has room for the curve.
        #expect(EyeRaster.drawableRadius(6, halfWidth: 6.5, halfHeight: 6, pitch: 1) == 5)
    }

    @Test("no radius, no rounding")
    func squareStaysSquare() {
        #expect(EyeRaster.drawableRadius(0, halfWidth: 10, halfHeight: 10, pitch: 2) == 0)
    }

    // The measured case: `eve`'s idle eye at the shipped grain came out a lozenge,
    // which is neither of the two things an eye may be.
    @Test("the shipped idle eye is not a diamond")
    func shippedEyeIsNotADiamond() {
        let manifest = BuiltInBuddy.manifest
        let spec = try? #require(manifest.expression(.idle)?.eye)
        guard let spec else { return }
        let frame = EyeRaster.frame(
            in: CGSize(width: manifest.face.width, height: manifest.face.height),
            pose: spec.pose, animation: EyeAnimation(), pitch: BuddyView.pixelSize)

        // A diamond has exactly one cell on its widest row's outermost columns and
        // tapers every row.
        let left = frame.lit.filter { $0.midX < manifest.face.width / 2 }
        let rows = Dictionary(grouping: left) { Int($0.midY / BuddyView.pixelSize) }
        let widths = rows.values.map { $0.count }.sorted()
        #expect(widths.count >= 3)
        // At least two rows share the widest count — a taper would give each row its
        // own.
        if let widest = widths.last {
            #expect(widths.filter { $0 == widest }.count >= 2)
        }
    }
}
