// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GaiaFTCL",
    platforms: [
        .macOS(.v14),   // Sonoma+ for Metal 3 and Swift 6 concurrency
    ],
    products: [
        .executable(name: "gaiaftcl", targets: ["gaiaftcl"]),
        .library(name: "GaiaFTCLCore", targets: ["GaiaFTCLCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(url: "https://github.com/nats-io/nats.swift.git", from: "0.4.0"),
    ],
    targets: [
        // ── CLI executable ──────────────────────────────────────────
        .executableTarget(
            name: "gaiaftcl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "GaiaFTCLCore",
            ],
            path: "Sources/gaiaftcl"
        ),

        // ── Shared framework ────────────────────────────────────────
        .target(
            name: "GaiaFTCLCore",
            dependencies: [
                .product(name: "Nats", package: "nats.swift"),
            ],
            path: "Sources/GaiaFTCLCore",
            resources: [
                .copy("Invariants/InvariantSeeds"),
                .copy("Pathogens/PathogenSeeds")
            ]
        ),

        // ── Tests ───────────────────────────────────────────────────
        .testTarget(
            name: "GaiaFTCLTests",
            dependencies: [
                "gaiaftcl",
                "GaiaFTCLCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tests/GaiaFTCLTests"
        ),
    ]
)
