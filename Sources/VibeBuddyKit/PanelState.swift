import Foundation

/// What the window is showing right now.
public enum PanelState: Sendable, Equatable {
    case hidden
    case pill
    case panel

    public var isVisible: Bool { self != .hidden }

    /// Only the expanded panel absorbs clicks over its whole frame; the pill absorbs a
    /// strip and `hidden` absorbs nothing — see `ClickThroughHostView`.
    public var absorbsFullFrame: Bool { self == .panel }

    public var allowsAnimation: Bool { isVisible }
}
