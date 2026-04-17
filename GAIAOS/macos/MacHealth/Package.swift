// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacHealth",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacHealth", targets: ["MacHealth"]),
    ],
    targets: [
        .target(
            name: "GaiaHealthRenderer",
            dependencies: [],
            path: "MetalRenderer/include",
            publicHeadersPath: ".",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(Context.packageDirectory)/MetalRenderer/lib",
                    "-lgaia_health_renderer",
                    "-lbiologit_md_engine",
                    "-lbiologit_usd_parser",
                    "-framework", "Metal",
                    "-framework", "QuartzCore",
                    "-framework", "CoreGraphics",
                ])
            ]
        ),
        .executableTarget(
            name: "MacHealth",
            dependencies: [
                .target(name: "GaiaHealthRenderer"),
            ],
            path: "MacHealth"
        ),
        .testTarget(
            name: "MacHealthTests",
            dependencies: ["MacHealth", "GaiaHealthRenderer"],
            path: "Tests"
        ),
    ]
)
