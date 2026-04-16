// swift-tools-version: 5.9
// SwiftTestRobit — McFusion Biologit Cell Test Harness
//
// Mirrors the TestRobit pattern from GaiaFusion but exercises the GaiaHealth
// biological cell: FFI bridge, state machine, zero-PII wallet, M/I/A epistemic
// chain, and WASM constitutional 8-export contract.
//
// Requires: macOS 14+, Xcode 15+, libbiologit_md_engine.a + libgaia_health_renderer.a
// built via: cargo build --release --target aarch64-apple-darwin
//
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import PackageDescription

let package = Package(
    name: "SwiftTestRobit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwiftTestRobit", targets: ["SwiftTestRobit"]),
    ],
    targets: [
        // The Rust static libs are pre-built by the Makefile / iq_install.sh
        // before this package is resolved.
        .systemLibrary(
            name: "BiologitMDEngine",
            path: "Sources/BiologitMDEngine",
            pkgConfig: nil
        ),
        .systemLibrary(
            name: "GaiaHealthRenderer",
            path: "Sources/GaiaHealthRenderer",
            pkgConfig: nil
        ),
        .executableTarget(
            name: "SwiftTestRobit",
            dependencies: [
                "BiologitMDEngine",
                "GaiaHealthRenderer",
            ],
            path: "Sources/SwiftTestRobit",
            linkerSettings: [
                // Link pre-built Rust static libraries
                .linkedLibrary("biologit_md_engine",    .when(platforms: [.macOS])),
                .linkedLibrary("gaia_health_renderer",  .when(platforms: [.macOS])),
                // Frameworks required by Metal renderer
                .linkedFramework("Metal",               .when(platforms: [.macOS])),
                .linkedFramework("QuartzCore",          .when(platforms: [.macOS])),
                .linkedFramework("AppKit",              .when(platforms: [.macOS])),
                // Search path for Rust build artifacts (copied to swift_testrobit directory)
                .unsafeFlags([
                    "-L.",
                ]),
            ]
        ),
    ]
)
