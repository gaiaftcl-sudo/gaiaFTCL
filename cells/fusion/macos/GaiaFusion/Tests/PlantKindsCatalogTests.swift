import XCTest
@testable import GaiaFusion

final class PlantKindsCatalogTests: XCTestCase {
    func testLegacyAliasesResolveToCanonicalKinds() {
        XCTAssertEqual(PlantKindsCatalog.resolve("virtual"), "tokamak")
        XCTAssertEqual(PlantKindsCatalog.resolve("real"), "tokamak")
        XCTAssertEqual(PlantKindsCatalog.resolve("icf"), "inertial")
        XCTAssertEqual(PlantKindsCatalog.resolve("pjmif"), "mif")
    }

    func testCanonicalKindsPassThrough() {
        for k in [
            "tokamak", "stellarator", "frc", "spheromak", "mirror", "inertial",
            "spherical_tokamak", "z_pinch", "mif",
        ] {
            XCTAssertEqual(PlantKindsCatalog.resolve(k), k)
        }
    }

    func testUnknownKindRefused() {
        XCTAssertNil(PlantKindsCatalog.resolve("not_a_plant_kind"))
    }

    func testSharedCatalogNonEmpty() {
        XCTAssertFalse(PlantKindsCatalog.shared.kinds.isEmpty)
    }

    func testKindAliasesExposedForAPI() {
        XCTAssertEqual(PlantKindsCatalog.kindAliases["icf"], "inertial")
        XCTAssertEqual(PlantKindsCatalog.kindAliases["pjmif"], "mif")
    }
}
