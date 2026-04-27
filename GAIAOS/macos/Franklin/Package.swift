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
            dependencies: ["FranklinUIKit"]
        ),
        .testTarget(
            name: "FranklinPresenceTests",
            dependencies: ["FranklinUIKit", "FranklinApp"]
        ),
    ]
)
