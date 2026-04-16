// swift-tools-version: 6.0
// MacHealth IQ/OQ/PQ — Separate qualification path
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import PackageDescription

let package = Package(
    name: "MacHealthQualification",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacHealthQualification", targets: ["MacHealthQualification"]),
    ],
    targets: [
        .executableTarget(
            name: "MacHealthQualification",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
