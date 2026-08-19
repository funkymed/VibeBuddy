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

    var body: some View {
        shape
            .fill(.black)
            .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .frame(width: max(metrics.drawnWidth, 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(state == .hidden ? 0 : 1)
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
