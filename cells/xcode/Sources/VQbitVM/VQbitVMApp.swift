import Foundation
import FusionCore
import GaiaFTCLCore
import GaiaGateKit
import VQbitSubstrate

private final class VmReadyPublisher: @unchecked Sendable {
    private let lock = NSLock()
    private var published = false
    private let client: NATSClient

    init(client: NATSClient) {
        self.client = client
    }

    /// **vm.ready** is published when **moored** only. τ is self-sovereign (URLSession + optional mesh) and does not gate readiness.
    func tryPublish() {
        lock.lock()
        defer { lock.unlock() }
        guard !published else { return }
        guard VQbitMeasurementGate.shared.mooringAcquired() else { return }
        let payload: [String: Any] = [
            "schema_version": 1,
            "timestamp_utc": Int(Date().timeIntervalSince1970),
            "cell_id": GaiaCellIdentity.uuid.uuidString,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        client.publish(subject: NATSConfiguration.vmReadySubject, payload: data)
        published = true
    }
}

@main
struct VQbitVMApp {
    static func main() {
        Task {
            await entry()
        }
        RunLoop.main.run()
    }

    private static func entry() async {
        let natsURL = NATSConfiguration.vqbitNATSURL
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
        client.subscribeSync(to: NATSConfiguration.tauSubject)
        client.subscribeSync(to: NATSConfiguration.franklinStageMooredSubject)
        client.subscribeSync(to: NATSConfiguration.franklinStageUnmooredSubject)

        let vmReady = VmReadyPublisher(client: client)

        let tauMonitor = TauSyncMonitor(
            onTick: { state in
                let label = state.source == .selfFetched ? "self" : "mesh"
                VQbitMeasurementGate.shared.recordTau(blockHeight: state.blockHeight, sourceLabel: label)
                vmReady.tryPublish()
            },
            onStale: {
                VQbitMeasurementGate.shared.notifyTauStaleFromMonitor()
            }
        )
        await tauMonitor.start()

        let pipeline = VQbitVMDeltaPipeline()
        let cellID = GaiaCellIdentity.uuid
        let pointsLog = ProcessInfo.processInfo.environment["GAIAFTCL_VQBIT_POINTS_LOG"].map { URL(fileURLWithPath: $0) }
            ?? GaiaInstallPaths.vqbitPointsLogURL

        Task {
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(30))
                publishHeartbeat(client: client, store: store)
            }
        }

        for await msg in client.messages {
            switch msg.subject {
            case NATSConfiguration.tauSubject:
                await tauMonitor.receiveMeshTau(msg.payload)
            case NATSConfiguration.franklinStageMooredSubject:
                VQbitMeasurementGate.shared.setMoored(true)
                vmReady.tryPublish()
            case NATSConfiguration.franklinStageUnmooredSubject:
                VQbitMeasurementGate.shared.setMoored(false)
            case SubstrateWireSubjects.s4Delta:
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
            default:
                break
            }
        }
    }

    private static func publishHeartbeat(client: NATSClient, store: ManifoldTensorStore) {
        let gate = VQbitMeasurementGate.shared
        let reason = gate.blockReason()
        let payload: [String: Any] = [
            "tau_block_height": gate.tauBlockHeightForHeartbeat(),
            "tau_source": gate.tauSourceLabelForHeartbeat(),
            "tau_stale": reason == .tauStaleOrAbsent,
            "moored": gate.mooringAcquired(),
            "tau_sync": gate.tauSynchronized(),
            "blocked_reason": String(describing: reason),
            "prims_active": store.primToRow.count,
            "timestamp_utc": Int(Date().timeIntervalSince1970),
            "schema_version": 2,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        client.publish(subject: NATSConfiguration.vmHeartbeatSubject, payload: data)
    }

    private static func parseNATSURL(_ url: String) -> (host: String, port: UInt16) {
        guard let u = URL(string: url), let host = u.host else {
            return ("127.0.0.1", 4222)
        }
        let port = UInt16(u.port ?? 4222)
        return (host, port)
    }
}
