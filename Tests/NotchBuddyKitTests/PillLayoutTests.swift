import Testing
import CoreGraphics
@testable import NotchBuddyKit

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

    // The rule that is easy to forget because it is invisible in the common
    // case: the pill and the notch are both centred, so equal ears align by
    // accident and unequal ones do not.
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

    // Hard-coded slot widths work until a buddy has a longer face or a manifest
    // changes its font size, at which point the content overflows a slot sized
    // for something else.
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

    // An alert and the counter say the same kind of thing; stacking them would
    // make the pill grow twice for one event.
    @Test("an alert takes the right ear over from the counter")
    func alertReplacesCounter() {
        let counter = PillLayout.resolve(geometry: notched, buddy: nil, sessionCount: 3)
        let alert = PillLayout.resolve(
            geometry: notched, buddy: nil, sessionCount: 3, alertText: "notch terminé")
        #expect(alert.rightWidth > counter.rightWidth)
    }

    // Asymmetric ears were geometrically fine — the pill was shifted so its hole
    // still landed on the cutout — and looked wrong: the notch is symmetric, so
    // a shape hanging further out on one side reads as misaligned.
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

    @Test("measuring an empty string costs nothing")
    func emptyMeasure() {
        #expect(PillLayout.measure("", size: 13, weight: .bold) == 0)
    }
}

/// A manifest can now ask for anything — the expression editor makes a 40 pt
/// face two clicks away — so the pill has a ceiling and the buddy gives way.
@Suite("Oversized buddies")
@MainActor
struct OversizedBuddyTests {

    private func giant() -> BuddyManifest {
        BuddyFile.parse("""
        size: 40

        idle (x #FFFFFF)
        (⊙▂⊙)(⊙▂⊙)(⊙▂⊙)
        """, id: "giant", name: "Giant").manifest!
    }

    @Test("an ear never grows past the cap, whatever the buddy asks")
    func slotIsCapped() {
        let layout = PillLayout.resolve(geometry: notched, buddy: giant(), sessionCount: 1)
        #expect(layout.leftWidth == PillLayout.maxSlotWidth)
        #expect(layout.rightWidth == PillLayout.maxSlotWidth)
    }

    @Test("the content box is the slot minus its padding")
    func contentBox() {
        let layout = PillLayout.resolve(geometry: notched, buddy: giant(), sessionCount: 1)
        let box = layout.contentBox()
        #expect(box.width == PillLayout.maxSlotWidth - PillLayout.slotPadding * 2)
        #expect(box.height < layout.height)
        #expect(box.height > 0)
    }

    // The vertical half of the fit: a 40 pt face is taller than a 38 pt notch,
    // so the scale has to come from the height even when the width fits.
    @Test("a line is taller than its point size")
    func lineHeightExceedsPointSize() {
        #expect(PillLayout.lineHeight(size: 40, family: nil) > 40)
        #expect(PillLayout.lineHeight(size: 12, family: nil) > 12)
    }

    @Test("the shipped buddies are unaffected by the cap")
    func shippedBuddiesFit() {
        let layout = PillLayout.resolve(
            geometry: notched, buddy: BuiltInBuddy.manifest, sessionCount: 2)
        #expect(layout.leftWidth < PillLayout.maxSlotWidth)
    }
}
