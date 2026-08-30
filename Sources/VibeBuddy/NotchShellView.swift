import SwiftUI
import VibeBuddyKit

/// The pill and the expanded panel are one shape with one identity.
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
    var onDismissSession: ((AgentSession) -> Void)?
    var dismissedCount = 0
    var onRestoreDismissed: (() -> Void)?
    var jumpNote: String?
    /// Passed down rather than built here: see `NotchPanel.timelines`.
    var timelines = SessionTimelineLoader()
    var gaze: PointerGaze?
    /// The request on screen, if there is one.
    var permission: PermissionRequestModel?
    var permissionWaiting = 0
    var onPermissionDeny: () -> Void = {}
    var onPermissionAllow: () -> Void = {}
    var onPermissionAlwaysAllow: () -> Void = {}
    var onPermissionAnswer: (String) -> Void = { _ in }
    /// Set while « Toujours autoriser » is waiting to be confirmed.
    var consent: PermissionConsent?
    var onConsentCancel: () -> Void = {}
    var onConsentConfirm: () -> Void = {}
    var groupByDirectory = true
    var jumpOnClick = true
    var showUsage = true
    /// The height the window is being drawn at, so the background can put its seam on
    /// the notch's edge rather than at a fixed fraction.
    var panelHeight: CGFloat = 0

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
                // Black for exactly the height of the real notch, then the panel's
                // own colour.
                .overlay(shape.fill(backgroundWash))
                // Measured off the reference: `(21,27,38)` over `(3,5,7)`, which is 7 %
                // of red and 12,5 % of blue — an edge catching the panel's own colour,
                // not a grey line drawn around it.
                .overlay(shape.strokeBorder(VibeTheme.Border.strong,
                                            lineWidth: VibeTheme.Border.width))
            pillContent
            panelContent
        }
        .frame(width: max(metrics.drawnWidth, 0))
        // The buddy is drawn once, outside both states, and slides between its two
        // homes. It used to live inside each of them: the pill's copy was dropped the
        // instant the state flipped and the panel's arrived 160 ms later, so opening
        // the notch made the face blink out and come back — filmed at 52 fps, eight
        // frames of empty black rectangle.
        .overlay(alignment: .topLeading) { travellingBuddy }
        // Offset the *whole* pill, shape included: applying it to the content alone
        // leaves the shape centred and hangs the buddy off the left edge.
        .offset(x: state == .panel ? 0 : (layout?.notchAlignmentOffset ?? 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(state == .hidden ? 0 : 1)
    }

    /// Absent while collapsed, so nothing of it is built until it is on screen.
    @ViewBuilder
    private var panelContent: some View {
        if state == .panel, showPanelContent {
            // One wrapper, one header, three possible bodies.
            DeployedPanel(header: deployedHeader) { deployedBody }
        }
    }

    private var deployedHeader: PanelHeader {
        PanelHeader(
            buddy: buddy, expression: expression,
            // The pill's own measurement, so the buddy is the same size whether the
            // panel is open or not.
            buddyBox: layout?.buddyBox ?? .zero,
            sessions: sessions, budget: budget, l10n: l10n,
            onSettings: onSettings, onQuit: onQuit)
    }

    @ViewBuilder
    private var deployedBody: some View {
        if let consent {
            PermissionConsentView(
                rule: consent.rule, diff: consent.diff,
                backupDirectory: consent.backupDirectory, l10n: l10n,
                onCancel: onConsentCancel, onConfirm: onConsentConfirm)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
        } else if let permission {
            PermissionPanelView(
                model: permission, waiting: permissionWaiting, l10n: l10n,
                onDeny: onPermissionDeny, onAllow: onPermissionAllow,
                onAlwaysAllow: onPermissionAlwaysAllow, onAnswer: onPermissionAnswer)
                .transition(
                    .opacity.combined(with: .offset(y: -6))
                        .animation(.easeOut(duration: 0.14)))
        } else {
            PanelContentView(
                sessions: sessions, buddy: buddy,
                buddyBox: layout?.buddyBox ?? .zero,
                expression: expression,
                budget: budget, usage: usage, l10n: l10n, locale: locale,
                onSettings: onSettings, onQuit: onQuit,
                onJump: onJump, onSelect: onSelect,
                onDismiss: onDismissSession, dismissedCount: dismissedCount,
                onRestoreDismissed: onRestoreDismissed, jumpNote: jumpNote,
                timelines: timelines,
                groupByDirectory: groupByDirectory,
                jumpOnClick: jumpOnClick, showUsage: showUsage
            )
            // Explicit, and deliberately not a bare fade: the contents rise the last
            // few points into place as the shape settles.
            .transition(
                .opacity.combined(with: .offset(y: -6))
                    .animation(.easeOut(duration: 0.14)))
        }
    }

    /// The fill laid over the black: nothing for the notch's own height, the panel's
    /// tint below it, and a fade between. The stops are fractions of the current height,
    /// which is why this is computed from `panelHeight` rather than written as
    /// constants: the panel is 292 pt tall for a shell command and 460 for a plan, and a
    /// gradient pinned at « 12 % from the top » would put the seam in a different place
    /// each time. The 127 Mo this repository once paid came from three gradients inside
    /// a body that depended on the animation phase; this one SwiftUI compares and leaves
    /// alone.
    private var backgroundWash: LinearGradient {
        guard state == .panel, panelHeight > 0 else {
            return LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
        }
        let notch = min(max(geometry?.pillHeight ?? 0, 0), panelHeight)
        let edge = notch / panelHeight
        // Half the notch's own height to fade over: long enough that no line is
        // visible, short enough that the colour has arrived well before the first row
        // of content.
        let settled = min(1, edge * 1.5)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: edge),
                .init(color: VibeTheme.Surface.tint, location: settled),
                .init(color: VibeTheme.Surface.tint, location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// The three slots: an ear, the cutout, an ear.
    @ViewBuilder
    private var pillContent: some View {
        if let layout, state != .hidden, state != .panel {
            HStack(spacing: 0) {
                // The buddy's seat, kept empty: it is drawn by `travellingBuddy`, which
                // outlives this view.
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
    @ViewBuilder
    private var travellingBuddy: some View {
        if let buddy, let layout, state != .hidden {
            let origin = buddyOrigin(layout)
            BuddyView(manifest: buddy, expression: expression, budget: budget,
                      fit: layout.buddyBox, gaze: gaze)
                // Poking the face.
                .contentShape(Rectangle())
                .onTapGesture { gaze?.amuse() }
                .padding(.leading, origin.x)
                .padding(.top, origin.y)
        }
    }

    /// Where the buddy sits, interpolated between its seat in the ear and its seat in
    /// the panel header.
    private func buddyOrigin(_ layout: PillLayout) -> CGPoint {
        let box = layout.buddyBox
        let collapsed = CGPoint(
            x: max(0, (layout.leftWidth - box.width) / 2),
            y: max(0, (layout.height - box.height) / 2))
        let deployed = CGPoint(x: PanelMetrics.contentInset.width,
                               y: PanelMetrics.contentInset.height)

        let from = layout.totalWidth
        let to = NotchPanel.panelMaxSize.width
        guard to > from else { return collapsed }
        let t = min(max((metrics.drawnWidth - from) / (to - from), 0), 1)
        // Eased, not linear: the width is on an ease-out, and a linear slide against it
        // reads as the buddy lagging behind its own pill.
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

    /// Top corners stay square on a notched display: both states hang off the top edge,
    /// and a radius there makes them float instead of flowing out.
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
