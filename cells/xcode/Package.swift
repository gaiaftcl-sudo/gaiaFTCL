// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GaiaFTCL",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "GaiaFTCL", targets: ["GaiaFTCL"]),
        .executable(name: "FranklinConsciousnessService", targets: ["FranklinConsciousnessService"]),
        .executable(name: "GaiaRTMGate", targets: ["GaiaRTMGate"]),
        .executable(name: "GaiaUSDGate", targets: ["GaiaUSDGate"]),
        .executable(name: "FranklinStartupPreflight", targets: ["FranklinStartupPreflight"]),
        .executable(name: "VQbitVM", targets: ["VQbitVM"]),
        .library(name: "GaiaFTCLCore", targets: ["GaiaFTCLCore"]),
        .library(name: "GaiaGateKit", targets: ["GaiaGateKit"]),
        .library(name: "VQbitSubstrate", targets: ["VQbitSubstrate"]),
    ],
    dependencies: [
        .package(path: "../../GAIAOS/macos/Franklin"),
        // Reality Composer Pro scene catalog — compiles .rkassets → .reality bundle.
        .package(path: "Package.realitycomposerpro"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
    ],
    targets: [
        // Pure-logic types (VQbit, DriftGuard, GAMPTypes, ReceiptChain, LanguageGameCatalog)
        // extracted from the executable so test targets can import them without AppKit/SwiftUI.
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
            dependencies: [.target(name: "VQbitSubstrate")],
            path: "Sources/GaiaGateKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
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
            name: "GaiaRTMGate",
            dependencies: [.target(name: "GaiaGateKit")],
            path: "Sources/GaiaRTMGate",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GaiaUSDGate",
            dependencies: [.target(name: "GaiaGateKit")],
            path: "Sources/GaiaUSDGate",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "FranklinStartupPreflight",
            dependencies: [.target(name: "GaiaGateKit")],
            path: "Sources/FranklinStartupPreflight",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Networking + VM primitives shared by the composite test suite.
        .target(
            name: "FusionCore",
            path: "Sources/FusionCore"
        ),
        .target(
            name: "FranklinConsciousness",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .target(name: "FusionCore"),
                .target(name: "QualificationKit"),
                .target(name: "VQbitSubstrate"),
                .target(name: "GaiaGateKit"),
            ],
            path: "Sources/FranklinConsciousness",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "FranklinConsciousnessService",
            dependencies: [
                .target(name: "FranklinConsciousness"),
            ],
            path: "Sources/FranklinConsciousnessService",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Scene director + procedural builder — RealityKit types extracted so test targets
        // can import and exercise Entity construction headless (no SwiftUI RealityView needed).
        .target(
            name: "GaiaFTCLScene",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
            ],
            path: "Sources/GaiaFTCLScene",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Mac tactical cell — SwiftUI + RealityKit + FoundationModels + FranklinUIKit.
        // Connects to the 9-cell sovereign mesh via NATS (FusionCore/NATSClient).
        .executableTarget(
            name: "GaiaFTCL",
            dependencies: [
                .product(name: "FranklinUIKit", package: "Franklin"),
                .target(name: "GaiaFTCLCore"),
                .target(name: "FusionCore"),
                .target(name: "QualificationKit"),
                .target(name: "GaiaFTCLScene"),
                .target(name: "GaiaGateKit"),
                .target(name: "VQbitSubstrate"),
                .product(name: "RealityKitContent", package: "Package.realitycomposerpro"),
            ],
            path: "Sources/GaiaFTCL",
            exclude: ["VQbitSubstrate.metal"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
            plugins: ["GaiaFTCLAvatarGate"]
        ),
        // GAMP 5 receipt writer and workspace locator shared by IQ/OQ/PQ suites.
        .target(
            name: "QualificationKit",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
            ],
            path: "Sources/QualificationKit"
        ),
        .testTarget(
            name: "GaiaFTCLTests",
            dependencies: [
                .product(name: "FranklinUIKit", package: "Franklin"),
                .target(name: "FusionCore"),
            ],
            path: "Tests/GaiaFTCLTests"
        ),
        .testTarget(
            name: "GaiaFTCLPresenceTests",
            dependencies: [
                .product(name: "FranklinUIKit", package: "Franklin"),
            ],
            path: "Tests/FranklinPresenceTests"
        ),
        // GAMP 5 IQ — Installation Qualification
        .testTarget(
            name: "GaiaFTCLIQTests",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .target(name: "FusionCore"),
                .target(name: "GaiaGateKit"),
                .target(name: "QualificationKit"),
            ],
            path: "Tests/GAMP5/IQ"
        ),
        // GAMP 5 OQ — Operational Qualification
        .testTarget(
            name: "GaiaFTCLOQTests",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .target(name: "QualificationKit"),
                .target(name: "GaiaFTCLScene"),
                .product(name: "RealityKitContent", package: "Package.realitycomposerpro"),
            ],
            path: "Tests/GAMP5/OQ"
        ),
        // GAMP 5 PQ — Performance Qualification
        .testTarget(
            name: "GaiaFTCLPQTests",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
                .target(name: "QualificationKit"),
            ],
            path: "Tests/GAMP5/PQ"
        ),
        // GAMP 5 MQ — MCP Live Qualification (requires GaiaFTCL app running on :8831)
        // Uses Apple Intelligence (FoundationModels) to generate fresh personas each run.
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
            name: "GaiaFTCLCoreTests",
            dependencies: [
                .target(name: "GaiaFTCLCore"),
            ],
            path: "Tests/GaiaFTCLCoreTests"
        ),
        .testTarget(
            name: "VQbitSubstrateTests",
            dependencies: [.target(name: "VQbitSubstrate")],
            path: "Tests/VQbitSubstrateTests"
        ),
        .plugin(
            name: "GaiaFTCLAvatarGate",
            capability: .buildTool(),
            path: "Plugins/CheckFranklinAvatarAssets"
        ),
    ]
)
