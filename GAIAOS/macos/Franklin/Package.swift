// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FranklinPresence",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FranklinUIKit", targets: ["FranklinUIKit"]),
        .executable(name: "FranklinApp", targets: ["FranklinApp"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FranklinUIKit",
            dependencies: [],
            resources: [
                .copy("Sounds/franklin_calm.aiff"),
                .copy("Sounds/franklin_bloom.aiff"),
                .copy("Sounds/franklin_refuse.aiff"),
            ]
        ),
        .executableTarget(
            name: "FranklinApp",
            dependencies: ["FranklinUIKit"],
            plugins: ["CheckFranklinAvatarAssets"]
        ),
        .testTarget(
            name: "FranklinPresenceTests",
            dependencies: ["FranklinUIKit", "FranklinApp"]
        ),
        // Build-time gate. Runs scripts/check_franklin_avatar_assets.zsh and
        // refuses to compile FranklinApp if any of the 6 required Passy
        // assets are missing, undersized, or hash-mismatched. The runtime
        // FranklinLaunchGate.swift reads the same required_assets.json so
        // build-time and runtime cannot disagree.
        .plugin(
            name: "CheckFranklinAvatarAssets",
            capability: .buildTool()
        ),
    ]
)
