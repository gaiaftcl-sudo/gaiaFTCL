// swift-tools-version: 6.0
// MacFusion IQ/OQ/PQ — Separate qualification path
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import PackageDescription

let package = Package(
    name: "MacFusionQualification",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacFusionQualification", targets: ["MacFusionQualification"]),
    ],
    targets: [
        .executableTarget(
            name: "MacFusionQualification",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
