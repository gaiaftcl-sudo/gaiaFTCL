import XCTest
@testable import GaiaFusion

final class CellStateTests: XCTestCase {
    func testHealthPercentConvertsToPercentScale() {
        let state = CellState(
            id: "node-01",
            name: "node-01",
            ipv4: "127.0.0.1",
            role: "test",
            health: 0.75,
            status: "ok",
            inputPlantType: .tokamak,
            outputPlantType: .stellarator,
            active: true
        )
        XCTAssertEqual(state.healthPercent, 75.0)
    }

    func testFallbackCellIsHealthyTextFallback() {
        let state = CellState.fallback
        XCTAssertEqual(state.name, "unknown")
        XCTAssertEqual(state.active, false)
    }
}
