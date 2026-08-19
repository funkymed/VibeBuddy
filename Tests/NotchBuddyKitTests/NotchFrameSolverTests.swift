import Testing
import CoreGraphics
@testable import NotchBuddyKit

private let notched = NotchGeometry(
    screenID: 1,
    screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    notchSize: CGSize(width: 250, height: 37)
)
private let plain = NotchGeometry(
    screenID: 2,
    screenFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
    notchSize: nil
)
private let pill = CGSize(width: 560, height: 32)

@Suite("NotchFrameSolver")
struct NotchFrameSolverTests {

    @Test("centred on a notched screen sits flush against the top edge")
    func flushOnNotch() {
        let f = NotchFrameSolver.frame(size: pill, geometry: notched, fraction: 0.5)
        #expect(f.maxY == notched.screenFrame.maxY)
    }

    // Anywhere but the cutout, a flush pill looks stuck to the menu bar rather
    // than flowing out of anything.
    @Test("off-centre keeps a gap below the top edge")
    func gapWhenFloating() {
        let f = NotchFrameSolver.frame(size: pill, geometry: notched, fraction: 0)
        #expect(f.maxY == notched.screenFrame.maxY - NotchFrameSolver.floatingTopGap)
    }

    @Test("centred on a screen without a notch still keeps the gap")
    func gapOnPlainScreen() {
        let f = NotchFrameSolver.frame(size: pill, geometry: plain, fraction: 0.5)
        #expect(f.maxY == plain.screenFrame.maxY - NotchFrameSolver.floatingTopGap)
    }

    @Test("the window never leaves the screen, whatever the fraction")
    func alwaysOnScreen() {
        for f in stride(from: -1.0, through: 2.0, by: 0.1) {
            let r = NotchFrameSolver.frame(size: pill, geometry: notched, fraction: CGFloat(f))
            #expect(r.minX >= notched.screenFrame.minX)
            #expect(r.maxX <= notched.screenFrame.maxX)
            #expect(r.maxY <= notched.screenFrame.maxY)
        }
    }

    @Test("a non-finite fraction falls back to centred instead of crashing")
    func nonFiniteFraction() {
        #expect(NotchFrameSolver.clampFraction(.nan) == 0.5)
        #expect(NotchFrameSolver.clampFraction(.infinity) == 0.5)
        #expect(NotchFrameSolver.clampFraction(-3) == 0)
        #expect(NotchFrameSolver.clampFraction(7) == 1)
    }

    // A second display has a non-zero origin. Positioning against width alone
    // would place the window on the wrong monitor.
    @Test("an external display is positioned in its own coordinate space")
    func externalScreenOrigin() {
        let f = NotchFrameSolver.frame(size: pill, geometry: plain, fraction: 0.5)
        #expect(f.minX >= plain.screenFrame.minX)
        #expect(f.maxX <= plain.screenFrame.maxX)
    }

    @Test("fraction round-trips through origin")
    func fractionRoundTrip() {
        for f in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
            let rect = NotchFrameSolver.frame(size: pill, geometry: notched, fraction: f)
            let back = NotchFrameSolver.fraction(forOriginX: rect.minX, size: pill, geometry: notched)
            // Centred anchors drop the edge padding, so they are exempt.
            if f != 0.5 { #expect(abs(back - f) < 0.02) }
        }
    }
}

@Suite("Snap magnets")
struct SnapTests {

    @Test("a near miss is caught by the magnet")
    func nearMissSnaps() {
        #expect(NotchFrameSolver.snap(fraction: 0.02, size: pill, geometry: notched) == 0)
        #expect(NotchFrameSolver.snap(fraction: 0.98, size: pill, geometry: notched) == 1)
    }

    @Test("a deliberate off-magnet position is left alone")
    func farPositionSurvives() {
        let f = NotchFrameSolver.snap(fraction: 0.28, size: pill, geometry: notched)
        #expect(f == 0.28)
    }

    // The threshold is in points, not fractions: a fixed fraction would make
    // magnets four times stickier on an ultrawide than on a laptop.
    @Test("magnet reach is the same physical distance on any display")
    func thresholdIsPhysical() {
        let narrow = NotchFrameSolver.snap(fraction: 0.05, size: pill, geometry: notched)
        let wide = NotchFrameSolver.snap(fraction: 0.05, size: pill, geometry: plain)
        // 5 % of the narrow screen is inside the magnet; 5 % of the wide one is not.
        #expect(narrow == 0)
        #expect(wide == 0.05)
    }
}

@Suite("PanelState")
struct PanelStateTests {

    @Test("only the expanded panel absorbs its whole frame")
    func absorbsFullFrame() {
        #expect(PanelState.panel.absorbsFullFrame)
        #expect(!PanelState.pill.absorbsFullFrame)
        #expect(!PanelState.hidden.absorbsFullFrame)
    }

    @Test("a hidden panel is neither visible nor animated")
    func hiddenIsInert() {
        #expect(!PanelState.hidden.isVisible)
        #expect(!PanelState.hidden.allowsAnimation)
    }

    @Test("every visible state may animate")
    func visibleStatesAnimate() {
        for s in [PanelState.pill, .speech, .panel] {
            #expect(s.isVisible)
            #expect(s.allowsAnimation)
        }
    }
}

@Suite("Pill sizing")
struct PillSizeTests {

    // The bug a screenshot caught and no test could: a pill exactly as wide and
    // tall as the cutout is black-on-black, hence invisible.
    @Test("the pill is always wider than the notch it hugs")
    func pillOverhangsTheNotch() {
        let size = NotchFrameSolver.pillSize(geometry: notched)
        #expect(size.width > notched.notchSize!.width)
        #expect(size.width == notched.notchSize!.width + NotchFrameSolver.defaultSlotWidth * 2)
    }

    @Test("the pill matches the notch height exactly so it reads as one shape")
    func pillMatchesNotchHeight() {
        let size = NotchFrameSolver.pillSize(geometry: notched)
        #expect(size.height == notched.notchSize!.height)
    }

    @Test("both content slots survive the sizing")
    func slotsFitOnBothSides() {
        let size = NotchFrameSolver.pillSize(geometry: notched)
        let overhang = size.width - notched.notchSize!.width
        #expect(overhang / 2 >= 56)  // the buddy needs 56 pt — RFC-005
    }

    @Test("a display without a notch gets a plain floating lozenge")
    func floatingPillOnPlainScreen() {
        let size = NotchFrameSolver.pillSize(geometry: plain)
        #expect(size.height == NotchFrameSolver.floatingPillHeight)
        #expect(size.width > 0)
    }

    @Test("asymmetric slots are honoured")
    func asymmetricSlots() {
        let size = NotchFrameSolver.pillSize(geometry: notched, leftSlot: 90, rightSlot: 30)
        #expect(size.width == notched.notchSize!.width + 120)
    }
}
