// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        // Foundation-only. Shared by the app and the hook executable.
        // MUST NOT import AppKit or SwiftUI: the hook binary is spawned by
        // Claude Code on every tool call, and dyld would load AppKit before
        // main() ever runs. See RFC-006, decision D4.
        .target(
            name: "VibeHookProtocol",
            path: "Sources/VibeHookProtocol"
        ),

        // App-side core: wake governance, animation budget, notch geometry,
        // performance probe. No UI.
        .target(
            name: "VibeBuddyKit",
            dependencies: ["VibeHookProtocol"],
            path: "Sources/VibeBuddyKit"
        ),

        .executableTarget(
            name: "VibeBuddy",
            dependencies: ["VibeBuddyKit", "VibeHookProtocol"],
            path: "Sources/VibeBuddy"
        ),

        // Stub until RFC-006. Kept here so the two-target layout — and the
        // no-AppKit constraint — is enforced from day one.
        .executableTarget(
            name: "vibe-hook",
            dependencies: ["VibeHookProtocol"],
            path: "Sources/VibeHook"
        ),

        .testTarget(
            name: "VibeBuddyKitTests",
            dependencies: ["VibeBuddyKit", "VibeHookProtocol"],
            path: "Tests/VibeBuddyKitTests"
        ),
    ]
)
