import Foundation
import SwiftData

@Model
public final class CachedSceneEntry {
    @Attribute(.unique) public var sceneID:           String
    public var file:              String
    public var scope:             String
    public var franklinCue:       String
    public var domain:            String
    public var approvedByVQbit:   Bool
    public var approvalTimestamp: Date?

    public init(
        sceneID:           String,
        file:              String,
        scope:             String,
        franklinCue:       String,
        domain:            String,
        approvedByVQbit:   Bool  = false,
        approvalTimestamp: Date? = nil
    ) {
        self.sceneID           = sceneID
        self.file              = file
        self.scope             = scope
        self.franklinCue       = franklinCue
        self.domain            = domain
        self.approvedByVQbit   = approvedByVQbit
        self.approvalTimestamp = approvalTimestamp
    }

    public static func domain(for sceneID: String) -> String {
        FranklinSceneDirector.catalog[sceneID]?.scope ?? "ALL"
    }
}
