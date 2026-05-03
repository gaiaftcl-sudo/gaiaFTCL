import Foundation
import FusionCore
import GaiaFTCLCore
import GaiaGateKit
import VQbitSubstrate

@main
struct VQbitVMApp {
    static func main() {
        Task {
            await entry()
        }
        RunLoop.main.run()
    }

    private static func entry() async {
        let natsURL = ProcessInfo.processInfo.environment["GAIAFTCL_NATS_URL"] ?? "nats://127.0.0.1:4222"
        guard let rowCountStr = ProcessInfo.processInfo.environment["GAIAFTCL_TENSOR_N"],
              let rowCount = UInt32(rowCountStr)
        else {
            FileHandle.standardError.write(Data("TERMINAL STATE: BLOCKED — GAIAFTCL_TENSOR_N unset (install script must inject QUALIFIED_N)\n".utf8))
            exit(2)
        }

        let tensorPath = ProcessInfo.processInfo.environment["GAIAFTCL_TENSOR_PATH"].map { URL(fileURLWithPath: $0) }
            ?? GaiaInstallPaths.manifoldTensorURL
        let overflowPath = ProcessInfo.processInfo.environment["GAIAFTCL_OVERFLOW_MAP_PATH"].map { URL(fileURLWithPath: $0) }
            ?? GaiaInstallPaths.vqbitPrimRowOverflowMapURL

        let hostPort = parseNATSURL(natsURL)
        let client = NATSClient(host: hostPort.host, port: hostPort.port)

        let store: ManifoldTensorStore
        do {
            store = try ManifoldTensorStore(tensorPath: tensorPath, overflowURL: overflowPath, rowCount: rowCount)
        } catch {
            FileHandle.standardError.write(Data("TERMINAL STATE: BLOCKED — tensor store: \(error)\n".utf8))
            exit(3)
        }

        do {
            let pool = try await SubstrateDatabase.shared.pool()
            let repo = FranklinDocumentRepository(db: pool)
            let (th, peers) = try repo.fetchPrimCalorieAndClosurePeers()
            VQbitContractThresholds.shared.replace(thresholds: th, peersByPrim: peers)
        } catch {
            FileHandle.standardError.write(
                Data("TERMINAL STATE: BLOCKED — constitutional threshold warm from substrate: \(error)\n".utf8)
            )
            exit(5)
        }

        let engine = SubstrateEngine()
        client.connect()

        var sawConnected = false
        for await state in client.stateStream {
            if case .connected = state { sawConnected = true; break }
            if case let .failed(msg) = state {
                FileHandle.standardError.write(Data("TERMINAL STATE: BLOCKED — NATS \(msg)\n".utf8))
                exit(4)
            }
        }
        guard sawConnected else {
            FileHandle.standardError.write(Data("TERMINAL STATE: BLOCKED — NATS not connected\n".utf8))
            exit(4)
        }

        client.subscribeSync(to: SubstrateWireSubjects.s4Delta)

        let pipeline = VQbitVMDeltaPipeline()
        let cellID = GaiaCellIdentity.uuid
        let pointsLog = ProcessInfo.processInfo.environment["GAIAFTCL_VQBIT_POINTS_LOG"].map { URL(fileURLWithPath: $0) }
            ?? GaiaInstallPaths.vqbitPointsLogURL

        for await msg in client.messages {
            guard msg.subject == SubstrateWireSubjects.s4Delta else { continue }
            do {
                let delta = try S4DeltaCodec.decode(msg.payload)
                VQbitMetalHarness.dispatchIdleTick()
                try pipeline.process(
                    delta: delta,
                    store: store,
                    engine: engine,
                    nats: client,
                    cellID: cellID,
                    pointsLogURL: pointsLog
                )
            } catch {
                FileHandle.standardError.write(Data("TERMINAL STATE: REFUSED — decode/projection: \(error)\n".utf8))
            }
        }
    }

    private static func parseNATSURL(_ url: String) -> (host: String, port: UInt16) {
        guard let u = URL(string: url), let host = u.host else {
            return ("127.0.0.1", 4222)
        }
        let port = UInt16(u.port ?? 4222)
        return (host, port)
    }
}
