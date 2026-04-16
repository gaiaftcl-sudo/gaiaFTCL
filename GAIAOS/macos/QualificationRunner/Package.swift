// swift-tools-version: 6.0
// QualificationRunner — Master IQ/OQ/PQ Orchestrator
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import PackageDescription

let package = Package(
    name: "QualificationRunner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QualificationRunner", targets: ["QualificationRunner"]),
    ],
    targets: [
        .executableTarget(
            name: "QualificationRunner",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
