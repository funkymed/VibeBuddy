import AppKit

/// Where the notch is, resolved once.
///
/// # Why this exists
///
/// The reference implementation computes this twice, with two different rules:
/// `AppDelegate.swift:98-112` reads `NSScreen.main`, while
/// `NotchWindow.swift:85-102` walks the screen list looking for a notched one.
/// They disagree whenever the user types in a window on a second display —
/// `NSScreen.main` follows *keyboard focus*, not hardware — and the pill jumps
/// screens or renders at the wrong width.
///
/// One resolver, one rule: the notched screen wins, and keyboard focus is never
/// consulted.
public struct NotchGeometry: Equatable, Sendable {

    /// Display the pill belongs to.
    public let screenID: CGDirectDisplayID
    public let screenFrame: CGRect
    /// Size of the hardware notch, or nil on a display without one.
    public let notchSize: CGSize?

    public var hasNotch: Bool { notchSize != nil }

    /// Height the collapsed pill should occupy. On a notched display it matches
    /// the notch so the pill flows out of the hole; elsewhere it is a plain
    /// menu-bar-height strip.
    public var pillHeight: CGFloat { notchSize?.height ?? 24 }

    public init(screenID: CGDirectDisplayID, screenFrame: CGRect, notchSize: CGSize?) {
        self.screenID = screenID
        self.screenFrame = screenFrame
        self.notchSize = notchSize
    }

    // MARK: - Resolution

    /// Resolve against the current screen layout.
    ///
    /// Preference order: the caller's remembered display if it still exists and
    /// still has a notch, then any notched display, then the first display.
    /// `NSScreen.main` is never consulted — see the type comment.
    @MainActor
    public static func resolve(preferredScreenID: CGDirectDisplayID? = nil) -> NotchGeometry? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        let notched = screens.filter { notchSize(of: $0) != nil }

        let chosen: NSScreen
        if let preferred = preferredScreenID,
           let match = screens.first(where: { displayID(of: $0) == preferred }),
           notchSize(of: match) != nil || notched.isEmpty {
            chosen = match
        } else if let first = notched.first {
            chosen = first
        } else {
            chosen = screens[0]
        }

        guard let id = displayID(of: chosen) else { return nil }
        return NotchGeometry(
            screenID: id,
            screenFrame: chosen.frame,
            notchSize: notchSize(of: chosen)
        )
    }

    /// Notch size for a screen, or nil if it has none.
    ///
    /// A notched display reports a non-zero top safe-area inset *and* splits its
    /// menu bar into two auxiliary areas with a gap between them. The gap is the
    /// notch. Checking only `safeAreaInsets.top` would also match displays with
    /// a rounded-corner inset and no notch at all.
    @MainActor
    public static func notchSize(of screen: NSScreen) -> CGSize? {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0 else { return nil }
        guard
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        else { return nil }
        return notchSize(
            screenWidth: screen.frame.width,
            leftAreaWidth: left.width,
            rightAreaWidth: right.width,
            topInset: topInset
        )
    }

    /// Pure form of the notch-width computation, so the arithmetic is testable
    /// without a display attached.
    public static func notchSize(
        screenWidth: CGFloat,
        leftAreaWidth: CGFloat,
        rightAreaWidth: CGFloat,
        topInset: CGFloat
    ) -> CGSize? {
        let width = screenWidth - leftAreaWidth - rightAreaWidth
        guard width > 0, topInset > 0 else { return nil }
        return CGSize(width: width, height: topInset)
    }

    @MainActor
    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID
    }
}
