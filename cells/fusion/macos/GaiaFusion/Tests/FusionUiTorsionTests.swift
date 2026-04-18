import XCTest
@testable import GaiaFusion

final class FusionUiTorsionTests: XCTestCase {
    func testScoreZeroWhenKleinDomTsxUsdClosed() {
        let health: [String: Any] = [
            "klein_bottle_closed": true,
            "wasm_surface": [
                "closed": true,
                "fusion_tsx_surface": ["closed": true],
            ],
            "usd_px": [
                "pxr_version_int": 2605,
                "in_memory_stage": true,
                "plant_control_viewport_prim": true,
            ],
        ]
        XCTAssertEqual(FusionUiTorsion.score01(health: health), 0.0, accuracy: 0.0001)
    }

    func testScoreQuarterWhenOnlyUsdOpen() {
        let health: [String: Any] = [
            "klein_bottle_closed": false,
            "wasm_surface": [
                "closed": false,
                "fusion_tsx_surface": ["closed": false],
            ],
            "usd_px": [
                "pxr_version_int": 2605,
                "in_memory_stage": true,
                "plant_control_viewport_prim": true,
            ],
        ]
        XCTAssertEqual(FusionUiTorsion.score01(health: health), 0.75, accuracy: 0.0001)
    }
}
