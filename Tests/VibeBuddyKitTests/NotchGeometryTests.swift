import Testing
import CoreGraphics
@testable import VibeBuddyKit

@Suite("NotchGeometry arithmetic")
struct NotchGeometryTests {
    // MacBook Pro 14" figures: the two auxiliary menu-bar areas flank the notch.
    @Test("notch width is the gap between the auxiliary areas")
    func notchWidthFromAuxiliaryAreas() {
        let size = NotchGeometry.notchSize(
            screenWidth: 1512,
            leftAreaWidth: 631,
            rightAreaWidth: 631,
            topInset: 37
        )
        #expect(size == CGSize(width: 250, height: 37))
    }

    // A display with a rounded-corner inset but no notch reports a top inset too.
    @Test("no gap means no notch")
    func noGapIsNoNotch() {
        let size = NotchGeometry.notchSize(
            screenWidth: 1512,
            leftAreaWidth: 756,
            rightAreaWidth: 756,
            topInset: 24
        )
        #expect(size == nil)
    }

    @Test("no inset means no notch")
    func noInsetIsNoNotch() {
        let size = NotchGeometry.notchSize(
            screenWidth: 2560,
            leftAreaWidth: 1000,
            rightAreaWidth: 1000,
            topInset: 0
        )
        #expect(size == nil)
    }

    @Test("pill height falls back to a menu bar strip without a notch")
    func pillHeightWithoutNotch() {
        let plain = NotchGeometry(
            screenID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            notchSize: nil
        )
        #expect(!plain.hasNotch)
        #expect(plain.pillHeight == 24)
    }

    @Test("pill height matches the notch when there is one")
    func pillHeightWithNotch() {
        let notched = NotchGeometry(
            screenID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchSize: CGSize(width: 250, height: 37)
        )
        #expect(notched.hasNotch)
        #expect(notched.pillHeight == 37)
    }
}
