// swift-tools-version: 5.9
// MacFranklin — macOS app shell for admin-cell / Franklin (same qualified zsh driver as CLI)

import PackageDescription

let package = Package(
    name: "MacFranklin",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacFranklin", targets: ["MacFranklin"])
    ],
    dependencies: [
        .package(path: "../AdminCellRunner")
    ],
    targets: [
        .executableTarget(
            name: "MacFranklin",
            dependencies: [
                .product(name: "AdminCellCore", package: "AdminCellRunner")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
