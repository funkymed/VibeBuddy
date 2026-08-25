import AppKit

/// Where the notch is, resolved once.
public struct NotchGeometry: Equatable, Sendable {
    public let screenID: CGDirectDisplayID
    public let screenFrame: CGRect
    public let notchSize: CGSize?

    public var hasNotch: Bool { notchSize != nil }

    public var pillHeight: CGFloat { notchSize?.height ?? 24 }

    public init(screenID: CGDirectDisplayID, screenFrame: CGRect, notchSize: CGSize?) {
        self.screenID = screenID
        self.screenFrame = screenFrame
        self.notchSize = notchSize
    }

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
