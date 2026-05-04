import Foundation
import Observation

public struct SceneEntry: Sendable, Hashable {
    public let sceneID:     String
    public let file:        String
    public let scope:       String
    public let franklinCue: String

    public init(sceneID: String, file: String, scope: String, franklinCue: String) {
        self.sceneID     = sceneID
        self.file        = file
        self.scope       = scope
        self.franklinCue = franklinCue
    }
}

@Observable
@MainActor
public final class FranklinSceneDirector {
    public var activeSceneID: String = "welcome"

    public init() {}

    public var active: SceneEntry {
        Self.catalog[activeSceneID] ?? Self.catalog["welcome"]!
    }

    public nonisolated static let catalog: [String: SceneEntry] = [
        "fusion-tokamak": SceneEntry(
            sceneID: "fusion-tokamak",
            file: "FusionTokamak.usda",
            scope: "FUSION",
            franklinCue: "Tokamak plasma containment — sovereign vQbit M⁸ domain"
        ),
        "fusion-stellarator": SceneEntry(
            sceneID: "fusion-stellarator",
            file: "FusionStellarator.usda",
            scope: "FUSION",
            franklinCue: "Stellarator HD — helical confinement, full C4 projection"
        ),
        "fusion-frc": SceneEntry(
            sceneID: "fusion-frc",
            file: "FusionFRC.usda",
            scope: "FUSION",
            franklinCue: "Field-reversed configuration — compact fusion vQbit"
        ),
        "health": SceneEntry(
            sceneID: "health",
            file: "HealthDomain.usda",
            scope: "HEALTH",
            franklinCue: "Health protocol — constitutional threshold C4"
        ),
        "lithography": SceneEntry(
            sceneID: "lithography",
            file: "LithographyDomain.usda",
            scope: "LITHOGRAPHY",
            franklinCue: "Silicon lithography — nanometre precision vQbit"
        ),
        "welcome": SceneEntry(
            sceneID: "welcome",
            file: "WelcomeScene.usda",
            scope: "ALL",
            franklinCue: "GaiaFTCL sovereign M⁸ — vQbit-gated scene"
        ),
    ]
}
