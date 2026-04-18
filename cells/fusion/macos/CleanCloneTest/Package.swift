// swift-tools-version: 6.0
// CleanCloneTest — Test qualification from fresh clone
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import PackageDescription

let package = Package(
    name: "CleanCloneTest",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CleanCloneTest", targets: ["CleanCloneTest"]),
    ],
    targets: [
        .executableTarget(
            name: "CleanCloneTest",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
