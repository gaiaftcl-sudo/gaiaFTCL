import Foundation
import FusionCore
import GaiaFTCLCore
import VQbitSubstrate

/// Publishes low S⁴ deltas (**0.05** on all axes) for every **active** `language_game_contracts` row so the local vQbit VM emits degraded C⁴ on **`gaiaftcl.substrate.c4.projection`**.
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

        let pool = try await SubstrateDatabase.shared.pool()
        let repo = FranklinDocumentRepository(db: pool)
        let surfaces = try repo.fetchLanguageGameContractSurfaces()
        guard !surfaces.isEmpty else {
            fputs("S4DegradeInject: no active language_game_contracts\n", stderr)
            throw NSError(domain: "S4DegradeInject", code: 3, userInfo: [NSLocalizedDescriptionKey: "no contracts"])
        }

        var seq = Int64(Date().timeIntervalSince1970 * 1000)
        for c in surfaces {
            guard let domain = c.domain?.lowercased() else { continue }
            let prim = GaiaFTCLPrimIdentity.primID(contractGameID: c.gameID, contractDomain: domain)
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
        /// Allow vQbit VM to fold four dims and publish C⁴ before Franklin **`--run-once`** reads **`ManifoldProjectionStore`**.
        try await Task.sleep(for: .seconds(3))
        client.disconnect()
        print("S4DegradeInject ok — degraded \(surfaces.count) contract surface(s)")
    }
}
