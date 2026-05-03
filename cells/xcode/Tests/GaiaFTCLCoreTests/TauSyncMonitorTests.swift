import Foundation
import GaiaFTCLCore
import Testing

@Suite("TauSyncMonitor")
struct TauSyncMonitorTests {
    @Test("TauSyncHTTPParsing parses plaintext tip height")
    func testTauSyncSelfFetchParsesHeight() {
        let mockData = "840123".data(using: .utf8)!
        let height = TauSyncHTTPParsing.blockHeight(fromPlaintextTipBody: mockData)
        #expect(height == 840_123)
    }

    @Test("TauSyncMonitor mesh τ accepted when higher than current")
    func testMeshTauAccepted() async throws {
        final class TickBox: @unchecked Sendable {
            var ticked = false
        }
        let box = TickBox()
        let monitor = TauSyncMonitor(
            onTick: { _ in box.ticked = true },
            onStale: {}
        )
        let payload = try JSONSerialization.data(withJSONObject: [
            "block_height": 840200,
            "block_hash": "abc",
            "timestamp_utc": 1746000000,
            "schema_version": 1,
        ])
        await monitor.receiveMeshTau(payload)
        #expect(box.ticked == true)
        let cur = await monitor.current
        #expect(cur?.blockHeight == 840200)
        #expect(cur?.source == .meshReceived)
    }
}
