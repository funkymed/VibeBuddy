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
    var jumpNote: String?
    var pixelSize: Double = Double(BuddyView.defaultPixelSize)
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
                sessions: sessions, buddy: buddy, expression: expression,
                budget: budget, usage: usage, l10n: l10n, locale: locale,
                onSettings: onSettings, onQuit: onQuit,
                onJump: onJump, jumpNote: jumpNote,
                pixelSize: pixelSize, groupByDirectory: groupByDirectory,
                jumpOnClick: jumpOnClick, showUsage: showUsage
            )
            // Explicit short fade: the default insertion transition fires at
            // the start of the growth and draws contents in a pill-sized shape.
            .transition(.opacity.animation(.easeOut(duration: 0.12)))
        }
    }

    /// The three slots: an ear, the cutout, an ear. One `HStack`, no per-slot
    /// offset — see RFC-002, « Notes d'implémentation ».
    @ViewBuilder
    private var pillContent: some View {
        if let layout, state != .hidden, state != .panel {
            HStack(spacing: 0) {
                // Anchored, not centred: animation frames differ in width and
                // centring makes the buddy shuffle sideways every frame.
                buddyContent
                    .padding(.leading, PillLayout.outerPadding)
                    .frame(width: layout.leftWidth, alignment: .leading)
                // The cutout: a hole, anything drawn here is invisible.
                Color.clear.frame(width: layout.notchWidth)
                rightSlot
                    .padding(.trailing, PillLayout.outerPadding)
                    .frame(width: layout.rightWidth, alignment: .trailing)
            }
            .frame(height: layout.height)
        }
    }

    @ViewBuilder
    private var buddyContent: some View {
        if let buddy, let layout {
            // The box is what lets an oversized manifest shrink to fit.
            BuddyView(manifest: buddy, expression: expression, budget: budget,
                      pixelSize: pixelSize, fit: layout.contentBox())
        }
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

    static func dot(for kind: SessionAlert.Kind) -> Color {
        switch kind {
        case .failed: return .red
        case .finished: return .green
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
