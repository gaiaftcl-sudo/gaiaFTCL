// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GaiaFTCLTestRobit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GaiaFTCLTestRobit",
            path: "Sources/GaiaFTCLTestRobit",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Foundation"),
                .unsafeFlags(["-L.", "-lgaia_metal_renderer"])
            ]
        )
    ]
)
