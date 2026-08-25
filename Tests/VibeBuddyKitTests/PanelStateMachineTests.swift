import Testing
import Foundation
@testable import VibeBuddyKit

/// The panel's re-entry guard and its frame stamp, exercised without a window. Both
/// defects these encode — the beachball and the collapse to a 460 pt hover strip — only
/// ever appeared at runtime; here they are ordinary assertions.
@Suite("Panel state machine")
@MainActor
struct PanelStateMachineTests {
    @Test("A move to the state already held applies nothing")
    func idempotentMove() {
        let machine = PanelStateMachine()
        var passes: [PanelStateMachine.Pass] = []
        machine.onApply = { passes.append($0) }

        machine.move(to: .hidden)  // it starts there

        #expect(passes.isEmpty)
        #expect(machine.state == .hidden)
        #expect(machine.frameGeneration == 0)
    }

    @Test("A real change applies exactly once, carrying the new state")
    func realMoveApplies() {
        let machine = PanelStateMachine()
        var passes: [PanelStateMachine.Pass] = []
        machine.onApply = { passes.append($0) }

        machine.move(to: .pill)

        #expect(machine.state == .pill)
        #expect(passes.count == 1)
        #expect(passes.first?.state == .pill)
        #expect(passes.first?.animated == true)
        #expect(passes.first?.generation == 1)
    }

    @Test("`animated` reaches the pass untouched")
    func animatedFlagIsCarried() {
        let machine = PanelStateMachine()
        var passes: [PanelStateMachine.Pass] = []
        machine.onApply = { passes.append($0) }

        machine.apply(animated: false)

        #expect(passes.map(\.animated) == [false])
    }

    @Test("A re-entrant apply produces one further pass, and only after the first returns")
    func reentryIsDeferred() {
        let machine = PanelStateMachine()
        var log: [String] = []
        var reentered = false
        machine.onApply = { pass in
            log.append("enter \(pass.generation)")
            if !reentered {
                reentered = true
                machine.apply()  // the tracking area reporting hover, in effect
                // If the inner call had run here, the next line would come after a
                // second "enter".
                log.append("still inside \(pass.generation)")
            }
            log.append("exit \(pass.generation)")
        }

        machine.apply()

        #expect(log == ["enter 1", "still inside 1", "exit 1", "enter 2", "exit 2"])
    }

    @Test("A re-entrant apply sees the state as it stands when the replay runs")
    func replayUsesTheLatestState() {
        let machine = PanelStateMachine()
        var passes: [PanelState] = []
        var moved = false
        machine.onApply = { pass in
            passes.append(pass.state)
            if !moved {
                moved = true
                machine.move(to: .panel)  // re-enters, so it only marks
            }
        }

        machine.move(to: .pill)

        #expect(passes == [.pill, .panel])
        #expect(machine.state == .panel)
    }

    @Test("A replay that never settles stops at ten passes")
    func runawayIsBounded() {
        let machine = PanelStateMachine()
        var count = 0
        machine.onApply = { _ in
            count += 1
            machine.apply()  // never converges, on purpose
        }

        machine.apply()

        #expect(count == PanelStateMachine.maxReapplyDepth)
        #expect(count == 10)
    }

    @Test("The depth counter is back at zero between two independent cycles")
    func depthResetsBetweenCycles() {
        let machine = PanelStateMachine()
        var count = 0
        machine.onApply = { _ in
            count += 1
            machine.apply()
        }

        machine.apply()
        let first = count
        count = 0
        machine.apply()

        // Were the reset done before the replay instead of after it, the bound would
        // never be reached at all; were it never done, the second cycle would run zero
        // times.
        #expect(first == 10)
        #expect(count == 10)
    }

    @Test("A converging replay is not truncated")
    func convergingReplayRunsToTheEnd() {
        let machine = PanelStateMachine()
        var remaining = 4
        var count = 0
        machine.onApply = { _ in
            count += 1
            if remaining > 0 { remaining -= 1; machine.apply() }
        }

        machine.apply()

        #expect(count == 5)
    }

    @Test("Every pass carries a strictly greater generation")
    func generationIsStrictlyIncreasing() {
        let machine = PanelStateMachine()
        var generations: [Int] = []
        machine.onApply = { generations.append($0.generation) }

        machine.move(to: .pill)
        machine.move(to: .panel)
        _ = machine.nextGeneration()
        machine.move(to: .pill)

        #expect(generations == [1, 2, 4])
        #expect(zip(generations, generations.dropFirst()).allSatisfy { $0 < $1 })
        #expect(machine.frameGeneration == 4)
    }

    @Test("`nil` means never stale")
    func nilGenerationIsAlwaysCurrent() {
        let machine = PanelStateMachine()
        #expect(machine.isCurrent(nil))
        _ = machine.nextGeneration()
        #expect(machine.isCurrent(nil))
    }

    @Test("A superseded generation is stale, the latest one is not")
    func supersededGenerationIsStale() {
        let machine = PanelStateMachine()
        let first = machine.nextGeneration()
        #expect(machine.isCurrent(first))

        let second = machine.nextGeneration()
        #expect(!machine.isCurrent(first))
        #expect(machine.isCurrent(second))
    }

    @Test("A pass's own generation goes stale as soon as another frame is driven")
    func passGenerationGoesStale() {
        let machine = PanelStateMachine()
        var pass: PanelStateMachine.Pass?
        machine.onApply = { pass = $0 }
        machine.move(to: .panel)

        #expect(machine.isCurrent(pass?.generation))
        _ = machine.nextGeneration()  // resizeToContent, in effect
        #expect(!machine.isCurrent(pass?.generation))
    }

    private static let allStates: [PanelState] = [.hidden, .pill, .speech, .panel]

    @Test("Hovering opens the panel from the pill, whatever else is going on")
    func hoverOpensFromPill() {
        for opening in [false, true] {
            for ask in [false, true] {
                #expect(PanelStateMachine.nextState(
                    from: .pill, hovering: true, opening: opening, holdingAnAsk: ask) == .panel)
            }
        }
    }

    @Test("Hovering changes nothing from any state but the pill")
    func hoverDoesNothingElsewhere() {
        // `.speech` included: the code has only ever opened from `.pill`, and a stale
        // comment in `NotchPanel` claiming otherwise is not the contract.
        for state in [PanelState.hidden, .speech, .panel] {
            for opening in [false, true] {
                for ask in [false, true] {
                    #expect(PanelStateMachine.nextState(
                        from: state, hovering: true,
                        opening: opening, holdingAnAsk: ask) == nil)
                }
            }
        }
    }

    @Test("Leaving closes an open panel that is neither growing nor holding an ask")
    func leavingClosesASettledPanel() {
        #expect(PanelStateMachine.nextState(
            from: .panel, hovering: false, opening: false, holdingAnAsk: false) == .pill)
    }

    @Test("Leaving never closes a panel that is still growing, or holding an ask")
    func leavingIsHeld() {
        #expect(PanelStateMachine.nextState(
            from: .panel, hovering: false, opening: true, holdingAnAsk: false) == nil)
        #expect(PanelStateMachine.nextState(
            from: .panel, hovering: false, opening: false, holdingAnAsk: true) == nil)
        #expect(PanelStateMachine.nextState(
            from: .panel, hovering: false, opening: true, holdingAnAsk: true) == nil)
    }

    @Test("Leaving changes nothing from any state but the open panel")
    func leavingDoesNothingElsewhere() {
        for state in [PanelState.hidden, .pill, .speech] {
            for opening in [false, true] {
                for ask in [false, true] {
                    #expect(PanelStateMachine.nextState(
                        from: state, hovering: false,
                        opening: opening, holdingAnAsk: ask) == nil)
                }
            }
        }
    }

    @Test("The whole table, in one place")
    func fullTable() {
        var seen: [String] = []
        for state in Self.allStates {
            for hovering in [false, true] {
                for opening in [false, true] {
                    for ask in [false, true] {
                        let next = PanelStateMachine.nextState(
                            from: state, hovering: hovering,
                            opening: opening, holdingAnAsk: ask)
                        if let next { seen.append("\(state)/\(hovering)/\(opening)/\(ask)→\(next)") }
                    }
                }
            }
        }
        // Exactly five of the thirty-two combinations move: four opens from the pill,
        // one close from a settled panel.
        #expect(seen.sorted() == [
            "panel/false/false/false→pill",
            "pill/true/false/false→panel",
            "pill/true/false/true→panel",
            "pill/true/true/false→panel",
            "pill/true/true/true→panel",
        ])
    }
}
