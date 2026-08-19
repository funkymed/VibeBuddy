import Foundation

/// What the window is showing right now.
///
/// The reference implementation has no such type, and pays for it twice:
/// `updateCollapsed` is a no-op whenever `isExpanded` is set
/// (`NotchWindow.swift:626-641`), a patch over two `onChange` handlers racing
/// inside one SwiftUI re-render; and a `suppressPrefsReposition` flag
/// (`:494-509`) mutes preference observers during a drag so they don't fire one
/// animation per stored property.
///
/// Both are symptoms of the same absence: no single place says what the window
/// is doing. With an explicit state, a transition applies exactly one frame, and
/// there is no race left to patch.
public enum PanelState: Sendable, Equatable {
    /// Off screen entirely. No hit region, no animation, no wakeups.
    case hidden
    /// The collapsed pill.
    case pill
    /// The pill, temporarily grown to carry an alert (RFC-012).
    case speech
    /// The full panel.
    case panel

    public var isVisible: Bool { self != .hidden }

    /// Whether the window should absorb clicks over its whole frame. Only the
    /// expanded panel does; the pill absorbs a strip, and `hidden` absorbs
    /// nothing — see `ClickThroughHostView`.
    public var absorbsFullFrame: Bool { self == .panel }

    /// The pill is a thin strip that must never occlude the menu bar around it;
    /// the panel is a real surface. Drives the animation budget too: only a
    /// visible state may animate.
    public var allowsAnimation: Bool { isVisible }
}
