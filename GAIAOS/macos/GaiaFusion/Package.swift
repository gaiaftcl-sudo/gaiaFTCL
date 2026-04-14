// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GaiaFusion",
    // Requires macOS 14 Sonoma or later for Metal 3 and Swift 6 concurrency
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "GaiaFusion", targets: ["GaiaFusion"]),
    ],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0"),
    ],
    targets: [
        // Rust Metal renderer - replaces OpenUSD bloat
        .target(
            name: "GaiaMetalRenderer",
            dependencies: [],
            path: "MetalRenderer/include",
            publicHeadersPath: ".",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(Context.packageDirectory)/MetalRenderer/lib",
                    "-lgaia_metal_renderer",
                    "-framework", "Metal",
                    "-framework", "QuartzCore",
                    "-framework", "CoreGraphics",
                ])
            ]
        ),
        .executableTarget(
            name: "GaiaFusion",
            dependencies: [
                .product(name: "Swifter", package: "swifter"),
                .target(name: "GaiaMetalRenderer"),
            ],
            path: "GaiaFusion",
            exclude: [
                "Shaders/SovereignShaders.metal",
                "Shaders/OpenUSDProxy.metal",
            ],
            // `.process` flattens nested trees and breaks `fusion-web/_next/static`; `.copy` preserves the Klein-bottle layout.
            resources: [
                .copy("Resources/fusion-web"),
                .copy("Resources/default.metallib"),
                .copy("Resources/fusion-sidecar-cell"),
                .copy("Resources/spec/native_fusion"),
                .copy("Resources/gaiafusion_substrate.wasm"),
                .copy("Resources/gaiafusion_substrate_bindgen.js"),
                .copy("Resources/Branding"),
                .copy("Resources/usd"),
            ]
        ),
        .testTarget(
            name: "GaiaFusionTests",
            dependencies: ["GaiaFusion"],
            path: "Tests"
        ),
    ]
)
