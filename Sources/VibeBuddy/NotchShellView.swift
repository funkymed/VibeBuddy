import SwiftUI
import VibeBuddyKit

/// The pill and the expanded panel are one shape with one identity.
///
/// Do not split them into two views: changing identity makes SwiftUI insert one
/// and remove the other, and the default fade cross-dissolves under the growth.
struct NotchShellView: View {
    let state: PanelState
    let geometry: NotchGeometry?
    @Bindable var budget: AnimationBudget
    @Bindable var metrics: PanelMetrics
    var alert: SessionAlert?
    var buddy: BuddyManifest?
    var expression: BuddyExpression = .sleeping
    /// Zero hides the counter entirely.
    var sessionCount: Int = 0
    var sessions: [AgentSession] = []
    /// Set once the opening animation is far enough along.
    var showPanelContent = false
    var usage: UsageState.Status = .unknown
    var l10n: Strings = .french
    var locale: Locale = .current
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    var onJump: (pid_t) -> Void = { _ in }
    var onSelect: ((String) -> Void)?
    var jumpNote: String?
    var gaze: PointerGaze?
    var groupByDirectory = true
    var jumpOnClick = true
    var showUsage = true

    /// Slot geometry, measured from what the ears actually contain.
    private var layout: PillLayout? {
        guard let geometry else { return nil }
        return PillLayout.resolve(
            geometry: geometry, buddy: buddy,
            sessionCount: sessionCount, alertText: alertText)
    }

    var body: some View {
        ZStack {
            shape
                .fill(.black)
                .overlay(shape.strokeBorder(PanelInk.stroke, lineWidth: 1))
            pillContent
            panelContent
        }
        .frame(width: max(metrics.drawnWidth, 0))
        // The buddy is drawn **once**, outside both states, and slides between
        // its two homes. It used to live inside each of them: the pill's copy
        // was dropped the instant the state flipped and the panel's arrived
        // 160 ms later, so opening the notch made the face blink out and come
        // back — filmed at 52 fps, eight frames of empty black rectangle.
        // Nothing in the real world disappears and reappears.
        .overlay(alignment: .topLeading) { travellingBuddy }
        // Offset the *whole* pill, shape included: applying it to the content
        // alone leaves the shape centred and hangs the buddy off the left edge.
        .offset(x: state == .panel ? 0 : (layout?.notchAlignmentOffset ?? 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(state == .hidden ? 0 : 1)
    }

    /// Absent while collapsed, so nothing of it is built until it is on screen.
    @ViewBuilder
    private var panelContent: some View {
        if state == .panel, showPanelContent {
            PanelContentView(
                sessions: sessions, buddy: buddy,
                // The pill's own measurement, so the buddy is the same size
                // whether the panel is open or not.
                buddyBox: layout?.buddyBox ?? .zero,
                expression: expression,
                budget: budget, usage: usage, l10n: l10n, locale: locale,
                onSettings: onSettings, onQuit: onQuit,
                onJump: onJump, onSelect: onSelect, jumpNote: jumpNote,
                groupByDirectory: groupByDirectory,
                jumpOnClick: jumpOnClick, showUsage: showUsage
            )
            // Explicit, and deliberately not a bare fade: the contents rise
            // the last few points into place as the shape settles. The default
            // insertion transition fires at the start of the growth and draws
            // contents in a pill-sized shape.
            .transition(
                .opacity.combined(with: .offset(y: -6))
                    .animation(.easeOut(duration: 0.14)))
        }
    }

    /// The three slots: an ear, the cutout, an ear. One `HStack`, no per-slot
    /// offset — see RFC-002, « Notes d'implémentation ».
    @ViewBuilder
    private var pillContent: some View {
        if let layout, state != .hidden, state != .panel {
            HStack(spacing: 0) {
                // The buddy's seat, kept empty: it is drawn by
                // `travellingBuddy`, which outlives this view.
                Color.clear
                    .frame(width: layout.leftWidth)
                // The cutout: a hole, anything drawn here is invisible.
                Color.clear.frame(width: layout.notchWidth)
                rightSlot
                    .padding(.trailing, PillLayout.counterPadding)
                    .frame(width: layout.rightWidth, alignment: .trailing)
            }
            .frame(height: layout.height)
            // The pill is an active zone: hovering it opens the panel.
            .pointingHandCursor()
        }
    }

    /// The one buddy, positioned by how far the shape has grown.
    ///
    /// Driven by `metrics.drawnWidth` rather than by `state`: that value is
    /// already animated, on the same curve and the same run-loop turn as the
    /// window's frame, so the face travels *with* the shape instead of needing
    /// a second animation kept in sync with it. Reading `state` here would jump
    /// the buddy to its panel seat on the first frame, because the state
    /// changes before the animation starts.
    @ViewBuilder
    private var travellingBuddy: some View {
        if let buddy, let layout, state != .hidden {
            let origin = buddyOrigin(layout)
            BuddyView(manifest: buddy, expression: expression, budget: budget,
                      fit: layout.buddyBox, gaze: gaze)
                // Poking the face. Two ways in, because two different things
                // own the click depending on the state: collapsed, the window
                // absorbs it and `NotchPanel.mouseUp` catches it; deployed,
                // SwiftUI owns hit testing and the window never hears about it.
                // Both call the same `amuse()`, and calling it twice is the
                // same as calling it once.
                .contentShape(Rectangle())
                .onTapGesture { gaze?.amuse() }
                .padding(.leading, origin.x)
                .padding(.top, origin.y)
        }
    }

    /// Where the buddy sits, interpolated between its seat in the ear and its
    /// seat in the panel header.
    private func buddyOrigin(_ layout: PillLayout) -> CGPoint {
        let box = layout.buddyBox
        let collapsed = CGPoint(
            x: max(0, (layout.leftWidth - box.width) / 2),
            y: max(0, (layout.height - box.height) / 2))
        let deployed = CGPoint(x: PanelMetrics.contentInset.width,
                               y: PanelMetrics.contentInset.height)

        let from = layout.totalWidth
        let to = NotchPanel.panelSize.width
        guard to > from else { return collapsed }
        let t = min(max((metrics.drawnWidth - from) / (to - from), 0), 1)
        // Eased, not linear: the width is on an ease-out, and a linear slide
        // against it reads as the buddy lagging behind its own pill.
        let e = 1 - pow(1 - t, 2)
        return CGPoint(x: collapsed.x + (deployed.x - collapsed.x) * e,
                       y: collapsed.y + (deployed.y - collapsed.y) * e)
    }

    /// Text an alert puts in the right ear, if one is up.
    private var alertText: String? {
        guard let alert, state == .speech else { return nil }
        return "\(alert.projectName) \(Self.label(for: alert.kind, l10n: l10n))"
    }

    /// One word for what happened, per kind.
    static func label(for kind: SessionAlert.Kind, l10n: Strings) -> String {
        switch kind {
        case .failed: return l10n.alertFailed
        case .finished: return l10n.alertFinished
        case .needsAttention: return l10n.alertWaiting
        }
    }

    /// Same vocabulary as `SessionStateStyle`: finished is orange everywhere.
    static func dot(for kind: SessionAlert.Kind) -> Color {
        switch kind {
        case .failed: return .red
        case .finished: return .orange
        case .needsAttention: return .blue
        }
    }

    /// The right ear: an alert while one is showing, the session count otherwise.
    @ViewBuilder
    private var rightSlot: some View {
        if let alert, let alertText {
            HStack(spacing: 4) {
                Circle()
                    .fill(Self.dot(for: alert.kind))
                    .frame(width: 5, height: 5)
                Text(alertText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelInk.primary)
                    .lineLimit(1)
            }
            .fixedSize()
        } else {
            sessionCounter
        }
    }

    @ViewBuilder
    private var sessionCounter: some View {
        if sessionCount > 0 {
            Text(PillLayout.counterText(sessionCount))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelInk.secondary)
                .shadow(color: PanelInk.tertiary, radius: 2)
                .fixedSize()
        }
    }

    /// Top corners stay square on a notched display: both states hang off the
    /// top edge, and a radius there makes them float instead of flowing out.
    private var shape: UnevenRoundedRectangle {
        let square = geometry?.hasNotch == true
        return UnevenRoundedRectangle(
            topLeadingRadius: square ? 0 : 10,
            bottomLeadingRadius: 12,
            bottomTrailingRadius: 12,
            topTrailingRadius: square ? 0 : 10
        )
    }
}
