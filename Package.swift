// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        // Foundation-only. Shared by the app and the hook executable.
        // MUST NOT import AppKit or SwiftUI: the hook binary is spawned by
        // Claude Code on every tool call, and dyld would load AppKit before
        // main() ever runs. See RFC-006, decision D4.
        .target(
            name: "NotchHookProtocol",
            path: "Sources/NotchHookProtocol"
        ),

        // App-side core: wake governance, animation budget, notch geometry,
        // performance probe. No UI.
        .target(
            name: "NotchBuddyKit",
            path: "Sources/NotchBuddyKit"
        ),

        .executableTarget(
            name: "NotchBuddy",
            dependencies: ["NotchBuddyKit", "NotchHookProtocol"],
            path: "Sources/NotchBuddy"
        ),

        // Stub until RFC-006. Kept here so the two-target layout — and the
        // no-AppKit constraint — is enforced from day one.
        .executableTarget(
            name: "notch-hook",
            dependencies: ["NotchHookProtocol"],
            path: "Sources/NotchHook"
        ),

        .testTarget(
            name: "NotchBuddyKitTests",
            dependencies: ["NotchBuddyKit"],
            path: "Tests/NotchBuddyKitTests"
        ),
    ]
)
