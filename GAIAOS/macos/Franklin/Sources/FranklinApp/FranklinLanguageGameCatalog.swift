import Foundation

struct FranklinLanguageGameCatalog {
    static let byFacet: [FranklinFacet: [AvatarLanguageGame]] = [
        .health: [
            AvatarLanguageGame(id: "LG-HEALTH-ROUTE-001", title: "Health route and policy decisions", scope: "local-mac", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-IQ-IDENTITY-001", title: "Identity contract verification", scope: "substrate", executable: true),
            AvatarLanguageGame(id: "LG-HEALTH-BATCH-RUN-001", title: "Health batch run catalog verb", scope: "substrate", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-IQ-PATHS-001", title: "Path integrity verification", scope: "substrate", executable: true),
        ],
        .fusion: [
            AvatarLanguageGame(id: "LG-FUSION-ROUTE-001", title: "Fusion route orchestration", scope: "local-mac", executable: true),
            AvatarLanguageGame(id: "LG-FUSION-PLANT-CYCLE-001", title: "Fusion plant cycle", scope: "substrate", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-IQ-HASHLOCKS-001", title: "Hash lock integrity sweep", scope: "substrate", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-OQ-FUSION-TESTS-001", title: "Fusion OQ test suite", scope: "substrate", executable: true),
        ],
        .lithography: [
            AvatarLanguageGame(id: "LG-LITHOGRAPHY-ROUTE-001", title: "Lithography route and characterization", scope: "local-mac", executable: true),
            AvatarLanguageGame(id: "LG-LITHO-EXPOSE-001", title: "Lithography exposure verb", scope: "substrate", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-PQ-EDU-AUDITOR-001", title: "Qualification co-sign review", scope: "substrate", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-OQ-LITHO-TESTS-001", title: "Lithography OQ suite", scope: "substrate", executable: true),
        ],
        .xcode: [
            AvatarLanguageGame(id: "LG-XCODE-ROUTE-001", title: "Xcode route and toolchain control", scope: "local-mac", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-IQ-XCODE-001", title: "Xcode toolchain verification", scope: "substrate", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-XCODE-NEW-CELL-001", title: "New cell scaffold flow", scope: "substrate", executable: true),
            AvatarLanguageGame(id: "LG-FRANKLIN-OQ-XCODE-TESTS-001", title: "Xcode OQ test suite", scope: "substrate", executable: true),
        ],
    ]

    static let shared: [AvatarLanguageGame] = [
        AvatarLanguageGame(id: "LG-FRANKLIN-OQ-AVATAR-TESTS-001", title: "Avatar OQ catalog run", scope: "local-mac", executable: true),
        AvatarLanguageGame(id: "LG-FRANKLIN-PQ-AVATAR-LIFELIKE-001", title: "Avatar PQ lifelike co-sign", scope: "local-mac", executable: true),
        AvatarLanguageGame(id: "LG-FRANKLIN-OQ-LIVE-CATALOG-001", title: "Live catalog closeout", scope: "substrate", executable: true),
    ]
}
