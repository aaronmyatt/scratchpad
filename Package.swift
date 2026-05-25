// swift-tools-version: 6.3
// Swift Package Manager manifest.
// Docs: https://www.swift.org/documentation/package-manager/
//
// Two executable products live here so they can share future internal modules
// (transport types, payload format) without crossing a network boundary at build
// time:
//   1. Scratchpad — the SwiftUI/AppKit desktop app (pinned window + dump display).
//   2. sp         — the CLI client that pipes stdin to the running app.
//
// Both currently target macOS only (see backlog/decisions/decision-1).

import PackageDescription

let package = Package(
    name: "Scratchpad",
    // macOS 14 (Sonoma) chosen as the floor: gives us modern SwiftUI window scenes
    // (`Window` / `WindowGroup` with `defaultSize`, `windowResizability`) without
    // forcing users onto bleeding-edge OS versions.
    // Ref: https://developer.apple.com/documentation/swiftui/window
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Scratchpad",
            path: "Sources/Scratchpad"
        ),
        .executableTarget(
            // The `sp` CLI. Kept as a separate target so it stays tiny — no SwiftUI,
            // no AppKit. Talks to the running app over HTTP (and later, a local socket).
            name: "sp",
            path: "Sources/sp"
        ),
        // Test target — reinstated TASK-38 (originally TASK-16) once full Xcode
        // 26.5 landed. Uses Swift Testing (the @Test / #expect macros, bundled
        // with the Xcode 16+ toolchain) rather than XCTest — modern syntax,
        // less ceremony, plays well with @MainActor on individual tests.
        // Ref: https://developer.apple.com/xcode/swift-testing/
        //
        // Depends on the Scratchpad executable target so tests can
        // `@testable import Scratchpad` and exercise pure-logic types
        // (InputHistory, EventStore, etc.) directly. SwiftPM has supported
        // testing executable targets since Swift 5.7; the @main attribute
        // doesn't collide with the test runner's own main because XCTest /
        // Swift Testing inject the runner entry point.
        // Ref: https://www.swift.org/documentation/package-manager/#testing-executable-targets
        .testTarget(
            name: "ScratchpadTests",
            dependencies: ["Scratchpad"],
            path: "Tests/ScratchpadTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
