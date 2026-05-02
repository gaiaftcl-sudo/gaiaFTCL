import Foundation
import FusionCore
import GaiaFTCLCore
import VQbitSubstrate

/// Publishes low S⁴ deltas for fusion + health prims so the vQbit VM can surface degraded C4 health.
@main
enum S4DegradeInject {
    static func main() async throws {
        let client = NATSClient(host: "127.0.0.1", port: 4222)
        client.connect()
        var connected = false
        waitNATS: for await state in client.stateStream {
            switch state {
            case .connected:
                connected = true
                break waitNATS
            case .failed(let msg):
                fputs("NATS failed: \(msg)\n", stderr)
                throw NSError(domain: "S4DegradeInject", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
            default:
                continue waitNATS
            }
        }
        guard connected else {
            throw NSError(domain: "S4DegradeInject", code: 2, userInfo: [NSLocalizedDescriptionKey: "not connected"])
        }

        let fusion = GaiaFTCLPrimIdentity.primID(contractGameID: "FUSION-001", contractDomain: "fusion")
        let health = GaiaFTCLPrimIdentity.primID(contractGameID: "HEALTH-001", contractDomain: "health")
        var seq = Int64(Date().timeIntervalSince1970 * 1000)
        for prim in [fusion, health] {
            for dim in UInt8(0) ..< 4 {
                seq += 1
                let wire = S4DeltaWire(
                    primID: prim,
                    dimension: dim,
                    oldValue: 0.5,
                    newValue: 0.05,
                    sequence: seq
                )
                let data = try S4DeltaCodec.encode(wire)
                client.publish(subject: SubstrateWireSubjects.s4Delta, payload: data)
            }
        }
        try await Task.sleep(for: .milliseconds(800))
        client.disconnect()
        print("S4DegradeInject ok")
    }
}
