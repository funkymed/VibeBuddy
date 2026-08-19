import SwiftUI
import NotchBuddyKit

/// The surface, and nothing on it.
///
/// RFC-002 delivers the window: a shape that collapses to a pill and expands to
/// a panel. What goes inside is RFC-005 (the buddy), RFC-007 (permissions) and
/// RFC-008 (sessions). Drawing placeholder content here would make the frame
/// measurements lie.
///
/// # One shape, never two
///
/// An earlier version switched between a `pill` view and a `panel` view. That
/// changes the view's *identity*, so SwiftUI inserts one and removes the other —
/// and its default transition is a fade. The result was a cross-dissolve
/// underneath the growth animation: the panel looked translucent while it
/// opened.
///
/// So there is exactly one shape here, always the same identity, and only its
/// dimensions change. Nothing fades because nothing is ever inserted or removed.
struct NotchShellView: View {
    let state: PanelState
    let geometry: NotchGeometry?
    @Bindable var budget: AnimationBudget
    @Bindable var metrics: PanelMetrics
    /// Set by RFC-012 while an alert is on screen.
    var alert: SessionAlert?
    var buddy: BuddyManifest?
    var expression: BuddyExpression = .sleeping
    /// Live agent sessions. Zero hides the counter entirely.
    var sessionCount: Int = 0
    var sessions: [AgentSession] = []
    /// Set once the opening animation is far enough along.
    var showPanelContent = false
    var usage: UsageState.Status = .unknown
    var l10n: Strings = .french
    var locale: Locale = .current
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

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
                .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
            pillContent
            panelContent
        }
        .frame(width: max(metrics.drawnWidth, 0))
        // The shift moves the *whole* pill, shape included.
        //
        // Applying it to the content alone was the first version and it was
        // visibly wrong: the shape stayed centred while its content slid left,
        // so the buddy hung off the left edge and a gap opened on the right.
        // The pill and its slots are one object — the notch alignment is a
        // property of where that object sits, not of what is inside it.
        .offset(x: state == .panel ? 0 : (layout?.notchAlignmentOffset ?? 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(state == .hidden ? 0 : 1)
    }

    /// The expanded panel's contents. Absent while collapsed, so nothing of it
    /// is built or updated until it is actually on screen.
    @ViewBuilder
    private var panelContent: some View {
        if state == .panel, showPanelContent {
            PanelContentView(
                sessions: sessions, buddy: buddy, expression: expression,
                budget: budget, usage: usage, l10n: l10n, locale: locale,
                onSettings: onSettings, onQuit: onQuit
            )
            // An explicit fade, short and on its own terms. The default
            // insertion transition fired at the start of the growth, which is
            // what made the contents appear inside a pill-sized shape.
            .transition(.opacity.animation(.easeOut(duration: 0.12)))
        }
    }

    /// The three slots: an ear, the cutout, an ear.
    ///
    /// Laid out as one `HStack` rather than two independently offset overlays.
    /// Offsets were how this worked first, and they were wrong the moment the
    /// ears differed in width — each one had to know the notch's half-width and
    /// its own padding, so changing either meant editing two constants that had
    /// no reason to know about each other.
    ///
    /// The slots carry no offset of their own: the whole pill is positioned by
    /// `body`, so the shape and its contents move together.
    @ViewBuilder
    private var pillContent: some View {
        if let layout, state != .hidden, state != .panel {
            HStack(spacing: 0) {
                // Anchored left, not centred. The frames of an animation differ
                // in width, and centring re-centres on every one of them — so a
                // buddy would shuffle sideways once a second instead of holding
                // still. The ears anchor outward, away from the cutout.
                buddyContent
                    .padding(.leading, PillLayout.outerPadding)
                    .frame(width: layout.leftWidth, alignment: .leading)
                // The cutout. Deliberately empty: it is a hole, and anything
                // drawn here is invisible by construction.
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
        if let buddy {
            BuddyView(manifest: buddy, expression: expression, budget: budget)
        }
    }

    /// Text an alert puts in the right ear, if one is up.
    private var alertText: String? {
        guard let alert, state == .speech else { return nil }
        return "\(alert.projectName) \(alert.kind == .failed ? l10n.alertFailed : l10n.alertFinished)"
    }

    /// The right ear: an alert while one is showing, the session count otherwise.
    @ViewBuilder
    private var rightSlot: some View {
        if let alert, let alertText {
            HStack(spacing: 5) {
                Circle()
                    .fill(alert.kind == .failed ? Color.red : Color.green)
                    .frame(width: 5, height: 5)
                Text(alertText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .fixedSize()
        } else {
            sessionCounter
        }
    }

    /// How many agents are running.
    ///
    /// Deliberately quieter than the buddy: the buddy carries state and should
    /// catch the eye, the count is a fact you look up. Same glow so the two read
    /// as one object, half the opacity so they do not compete.
    ///
    /// Hidden at zero rather than showing `×0` — an absence is better said by
    /// silence than by a number.
    @ViewBuilder
    private var sessionCounter: some View {
        if sessionCount > 0 {
            Text(PillLayout.counterText(sessionCount))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
                .shadow(color: .white.opacity(0.35), radius: 2)
                .fixedSize()
        }
    }

    /// Top corners stay square on a notched display: both the pill and the open
    /// panel hang off the top edge of the screen, so a radius there would make
    /// them float instead of flowing out of the cutout. Only the bottom edge is
    /// free, and only it gets rounded.
    ///
    /// The same radii serve both states on purpose — an animated corner radius
    /// is one more thing that can lag behind the frame and betray the illusion.
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
