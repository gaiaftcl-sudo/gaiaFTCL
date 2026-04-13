import XCTest
@testable import GaiaFusion

final class SwapLifecycleTests: XCTestCase {
    func testSwapLifecycleAdvances() {
        var swap = SwapState(
            requestID: "req-1",
            cellID: "cell-01",
            inputPlantType: "tokamak",
            outputPlantType: "stellarator",
            createdAtUtc: "2026-01-01T00:00:00Z",
            lifecycle: .requested
        )

        swap.advance()
        XCTAssertEqual(swap.lifecycle, .draining)
        swap.advance()
        XCTAssertEqual(swap.lifecycle, .committed)
        swap.advance()
        XCTAssertEqual(swap.lifecycle, .verified)
        swap.advance()
        XCTAssertEqual(swap.lifecycle, .verified)
    }

    func testSwapLifecycleStartsRequested() {
        let swap = SwapState(
            requestID: "req-2",
            cellID: "cell-02",
            inputPlantType: "mirror",
            outputPlantType: "inertial",
            createdAtUtc: "2026-01-01T00:00:00Z"
        )
        XCTAssertEqual(swap.lifecycle, .requested)
    }

    func testExplicitSwapKindPassthrough() {
        let explicitInput = PlantType.normalized(raw: "frc")
        let explicitOutput = PlantType.normalized(raw: "mirror")
        XCTAssertEqual(explicitInput, .frc)
        XCTAssertEqual(explicitOutput, .mirror)
    }
}
