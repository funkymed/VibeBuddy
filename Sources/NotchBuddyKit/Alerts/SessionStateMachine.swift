import Foundation

/// Turns a stream of transcript readings into state changes and alerts.
///
/// Pure: `(state, observation) → (state, alert?)`. No clocks, no I/O, no
/// randomness — every transition can be asserted directly, which matters
/// because the failure modes here are all "fired when it should not have".
///
/// # The rule that shapes everything
///
/// **An alert fires on a transition, never on a state.** A session that has
/// finished stays finished until something else happens; refreshing the view,
/// re-reading the transcript, or waking from sleep must not produce a second
/// notification for the same completed turn. The reference implementation gets
/// this wrong in the other direction — it infers completion from inactivity, so
/// a long-thinking turn looks finished and then unfinished again.
public enum SessionStateMachine {

    /// Next state, and the alert that transition deserves.
    public static func advance(
        from current: SessionActivity,
        observing observation: SessionObservation
    ) -> (state: SessionActivity, alert: SessionAlert.Kind?) {

        // A dead session has no state worth reporting, and must never alert:
        // the process is gone, so any "it finished" would be about something
        // the user already knows.
        guard observation.isLive else { return (.idle, nil) }

        // A running tool always wins. This is what stops a subagent's `result`
        // entry from reading as the end of the turn — the parent is still
        // working, so `turnEnded` cannot be reached.
        if observation.action != .none {
            return (.working, nil)
        }

        // Subagents still in flight mean the turn is not over, whatever else the
        // tail says. Alerting on every delegation is the single most likely way
        // to make these notifications worthless.
        if observation.subagentsRunning > 0 {
            return (.working, nil)
        }

        guard observation.turnEnded else {
            // Nothing running, no completion marker: alive but between things.
            return (current == .working ? .working : .idle, nil)
        }

        let destination: SessionActivity = observation.lastResultWasError ? .failed : .finished

        // Already there — the transcript has not moved, so neither should we.
        guard current != destination else { return (destination, nil) }

        // Arriving at completion from anywhere is worth saying once.
        let kind: SessionAlert.Kind = destination == .failed ? .failed : .finished
        return (destination, kind)
    }
}
