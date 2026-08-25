import Foundation

/// Turns a stream of transcript readings into state changes and alerts.
public enum SessionStateMachine {
    public static func advance(
        from current: SessionActivity,
        observing observation: SessionObservation
    ) -> (state: SessionActivity, alert: SessionAlert.Kind?) {
        guard observation.isLive else { return (.idle, nil) }

        // A question with no answer beats everything below, including a running tool:
        // `ExitPlanMode` is classified as planning, so checking the action first would
        // report work in progress for an agent standing still.
        if observation.awaitingAnswer {
            return (.awaiting, current == .awaiting ? nil : .needsAttention)
        }

        // A running tool wins: a subagent's `result` is not the parent's turn end.
        if observation.action != .none {
            return (.working, nil)
        }

        if observation.subagentsRunning > 0 {
            return (.working, nil)
        }

        guard observation.turnEnded else {
            return (current == .working ? .working : .idle, nil)
        }

        let destination: SessionActivity = observation.lastResultWasError ? .failed : .finished

        guard current != destination else { return (destination, nil) }

        let kind: SessionAlert.Kind = destination == .failed ? .failed : .finished
        return (destination, kind)
    }
}
