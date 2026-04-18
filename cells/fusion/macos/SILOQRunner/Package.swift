// swift-tools-version: 6.0
// SILOQRunner — Software-in-the-Loop OQ Orchestrator
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import PackageDescription

let package = Package(
    name: "SILOQRunner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SILOQRunner", targets: ["SILOQRunner"]),
    ],
    targets: [
        .executableTarget(
            name: "SILOQRunner",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
