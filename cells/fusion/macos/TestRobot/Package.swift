// swift-tools-version: 6.0
// TestRobot — Performance Qualification Orchestrator
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import PackageDescription

let package = Package(
    name: "TestRobot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TestRobot", targets: ["TestRobot"]),
    ],
    targets: [
        .executableTarget(
            name: "TestRobot",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
