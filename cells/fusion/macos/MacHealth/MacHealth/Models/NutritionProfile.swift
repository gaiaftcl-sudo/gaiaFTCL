// NutritionProfile.swift — declarative C4 + monitoring handles (schema-aligned) [I]
import Foundation

/// Mirrors `cells/health/schemas/nutrition/user_nutrition_profile.schema.json` — no raw PHI.
struct NutritionProfile: Codable, Equatable {
    var schemaVersion: String
    var ethicalFrameworkEnum: String?
    var religiousFrameworkEnum: String?
    var allergens: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ethicalFrameworkEnum = "ethical_framework"
        case religiousFrameworkEnum = "religious_framework"
        case allergens
    }
}
