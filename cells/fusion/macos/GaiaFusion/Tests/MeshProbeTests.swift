import XCTest
@testable import GaiaFusion

@MainActor final class MeshProbeTests: XCTestCase {
    func testProjectionPayloadDefaults() {
        let manager = MeshStateManager()
        let projection = manager.projectionPayload()
        XCTAssertEqual(projection.meshTotal, MeshStateManager.MeshConstants.meshNodeCount)
        XCTAssertNotNil(projection.lastUpdatedUtc)
    }

    func testProjectionReportsRecentSwaps() {
        let manager = MeshStateManager()
        let result = manager.requestSwap(cellID: "cell-01", input: "tokamak", output: "stellarator")
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "quorum_violation")
        let projection = manager.projectionPayload()
        XCTAssertEqual(projection.swapsRecent.count, 0)
    }
}
