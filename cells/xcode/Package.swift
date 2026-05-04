// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GaiaFTCL",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "GaiaRTMGate", targets: ["GaiaRTMGate"]),
        .executable(name: "FranklinConsciousnessService", targets: ["FranklinConsciousnessService"]),
        .executable(name: "VQbitVM", targets: ["VQbitVM"]),
        .executable(name: "S4DegradeInject", targets: ["S4DegradeInject"]),
        .executable(name: "QuantumOQInjector", targets: ["QuantumOQInjector"]),
        .library(name: "GaiaFTCLCore", targets: ["GaiaFTCLCore"]),
        .library(name: "GaiaGateKit", targets: ["GaiaGateKit"]),
        .library(name: "VQbitSubstrate", targets: ["VQbitSubstrate"]),
        .library(name: "FranklinConsciousness", targets: ["FranklinConsciousness"]),
        .library(name: "QualificationKit", targets: ["QualificationKit"]),
        .library(name: "GaiaFTCLScene", targets: ["GaiaFTCLScene"]),
        .library(name: "GaiaFTCL", targets: ["GaiaFTCL"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "GaiaFTCLCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/GaiaFTCLCore"
        ),
        .target(
            name: "VQbitSubstrate",
            path: "Sources/VQbitSubstrate",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "GaiaGateKit",
            dependencies: [
                .target(name: "VQbitSubstrate"),
                .target(name: "GaiaFTCLCore"),
            ],
            path: "Sources/GaiaGateKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "FusionCore",
            path: "Sources/FusionCore"
        ),
        .target(
            name: "QualificationKit",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
            ],
            path: "Sources/QualificationKit"
        ),
        .target(
            name: "FranklinConsciousness",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .target(name: "FusionCore"),
                .target(name: "VQbitSubstrate"),
                .target(name: "GaiaGateKit"),
            ],
            path: "Sources/FranklinConsciousness",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "FranklinConsciousnessService",
            dependencies: [
                .target(name: "FranklinConsciousness"),
            ],
            path: "Sources/FranklinConsciousnessService",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "VQbitVM",
            dependencies: [
                .target(name: "FusionCore"),
                .target(name: "GaiaFTCLCore"),
                .target(name: "GaiaGateKit"),
                .target(name: "VQbitSubstrate"),
            ],
            path: "Sources/VQbitVM",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "S4DegradeInject",
            dependencies: [
                .target(name: "FusionCore"),
                .target(name: "GaiaFTCLCore"),
                .target(name: "VQbitSubstrate"),
            ],
            path: "Sources/S4DegradeInject",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "QuantumOQInjector",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .target(name: "VQbitSubstrate"),
                .target(name: "FusionCore"),
                .target(name: "GaiaGateKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/QuantumOQInjector",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GaiaRTMGate",
            dependencies: [.target(name: "GaiaGateKit")],
            path: "Sources/GaiaRTMGate",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "GaiaFTCLScene",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .target(name: "GaiaGateKit"),
            ],
            path: "Sources/GaiaFTCLScene",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("RealityKit"),
                .linkedFramework("SwiftData"),
            ]
        ),
        .target(
            name: "GaiaFTCL",
            dependencies: [
                .target(name: "GaiaFTCLScene"),
                .target(name: "GaiaFTCLCore"),
                .target(name: "VQbitSubstrate"),
                .target(name: "GaiaGateKit"),
                .target(name: "FusionCore"),
                .target(name: "FranklinConsciousness"),
            ],
            path: "Sources/GaiaFTCL",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("RealityKit"),
                .linkedFramework("SwiftData"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "GaiaFTCLCoreTests",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
            ],
            path: "Tests/GaiaFTCLCoreTests"
        ),
        .testTarget(
            name: "VQbitSubstrateTests",
            dependencies: [
                .target(name: "VQbitSubstrate"),
                .target(name: "GaiaFTCLCore"),
            ],
            path: "Tests/VQbitSubstrateTests"
        ),
        .testTarget(
            name: "FranklinSelfReviewMQTests",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .target(name: "FranklinConsciousness"),
                .target(name: "VQbitSubstrate"),
                .target(name: "GaiaGateKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/FranklinSelfReviewMQTests"
        ),
        .testTarget(
            name: "GaiaFTCLMQTests",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .target(name: "QualificationKit"),
                .target(name: "FranklinConsciousness"),
                .target(name: "VQbitSubstrate"),
                .target(name: "GaiaGateKit"),
            ],
            path: "Tests/GAMP5/MQ"
        ),
        .testTarget(
            name: "GaiaFTCLPQTests",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .target(name: "FranklinConsciousness"),
                .target(name: "VQbitSubstrate"),
                .target(name: "GaiaGateKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/GAMP5/PQ"
        ),
    ]
)
