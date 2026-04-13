import XCTest
@testable import GaiaFusion

final class FusionFacilityWireframeGeometryTests: XCTestCase {
    func testAllCanonicalKindsEmitNonEmptySegments() {
        let kinds: [PlantType] = [
            .tokamak, .stellarator, .frc, .spheromak, .mirror, .inertial,
            .sphericalTokamak, .zPinch, .mif,
        ]
        for k in kinds {
            let v = FusionFacilityWireframeGeometry.vertexFloats(for: k)
            XCTAssertGreaterThan(v.count, 24, "kind \(k.rawValue)")
            XCTAssertEqual(v.count % 3, 0)
        }
    }

    func testUnknownFallsBackToTokamakTopology() {
        let u = FusionFacilityWireframeGeometry.vertexFloats(for: .unknown)
        let t = FusionFacilityWireframeGeometry.vertexFloats(for: .tokamak)
        XCTAssertEqual(u.count, t.count)
    }

    func testShaderIndicesAreStable() {
        XCTAssertEqual(FusionFacilityWireframeGeometry.shaderPlantKindIndex(.inertial), 0)
        XCTAssertEqual(FusionFacilityWireframeGeometry.shaderPlantKindIndex(.mif), 8)
        XCTAssertEqual(FusionFacilityWireframeGeometry.shaderPlantKindIndex(.unknown), 255)
    }

    func testLowLODHasFewerVerticesThanHighForICF() {
        let low = FusionFacilityWireframeGeometry.vertexFloats(for: .inertial, lod: .low)
        let high = FusionFacilityWireframeGeometry.vertexFloats(for: .inertial, lod: .high)
        XCTAssertGreaterThan(high.count, low.count)
    }

    func testWireframeLODThreshold() {
        XCTAssertEqual(FusionFacilityWireframeGeometry.wireframeLOD(drawableMinDimensionPoints: 300), .low)
        XCTAssertEqual(FusionFacilityWireframeGeometry.wireframeLOD(drawableMinDimensionPoints: 800), .high)
    }
}
