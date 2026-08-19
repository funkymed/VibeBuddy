import Testing
@testable import NotchBuddyKit

@Suite("AnimationBudget")
@MainActor
struct AnimationBudgetTests {

    @Test("still means no clock at all, not a slow one")
    func stillIsZero() {
        let budget = AnimationBudget()
        budget.set(.still)
        #expect(budget.frameRate == 0)
        #expect(budget.isPaused)
        #expect(!budget.allowsImplicitAnimations)
    }

    // The rule the reference breaks: an off-screen pill must cost nothing,
    // whatever Claude happens to be doing.
    @Test("hidden beats busy")
    func hiddenWinsOverBusy() {
        let budget = AnimationBudget()
        budget.update(isVisible: false, isBusy: true)
        #expect(budget.tier == .still)
        #expect(budget.frameRate == 0)
    }

    @Test("visible and idle draws ambient")
    func visibleIdleIsAmbient() {
        let budget = AnimationBudget()
        budget.update(isVisible: true, isBusy: false)
        #expect(budget.tier == .ambient)
        #expect(budget.frameRate == 8)
        #expect(!budget.isPaused)
    }

    @Test("visible and busy draws lively")
    func visibleBusyIsLively() {
        let budget = AnimationBudget()
        budget.update(isVisible: true, isBusy: true)
        #expect(budget.tier == .lively)
        #expect(budget.frameRate == 30)
        #expect(budget.allowsImplicitAnimations)
    }

    @Test("minimumInterval is usable by TimelineView")
    func minimumIntervalIsSane() {
        let budget = AnimationBudget()
        budget.set(.lively)
        #expect(abs(budget.minimumInterval - 1.0 / 30) < 0.0001)
        budget.set(.ambient)
        #expect(abs(budget.minimumInterval - 1.0 / 8) < 0.0001)
    }

    @Test("implicit animations are forbidden below lively")
    func implicitAnimationsGated() {
        let budget = AnimationBudget()
        for tier in AnimationBudget.Tier.allCases {
            budget.set(tier)
            #expect(budget.allowsImplicitAnimations == (tier == .lively))
        }
    }
}
