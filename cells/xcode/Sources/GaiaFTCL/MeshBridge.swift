// MeshBridge.swift — Connects the Mac GaiaFTCL app to the sovereign **mesh** (external mesh nodes).
//
// Role in the mesh topology:
//   • Connects OUT to wallet_gate (port 8803) across Helsinki/Nuremberg mesh endpoints
//   • Round-robins through GuestNetworkDefaults.natsMeshEndpoints on failure
//   • Subscribes to gaiaftcl.> on the NATS broker
//   • Decodes inbound vQbit payloads → VQbit → VQbitStore (all four domains)
//   • Publishes the Mac cell's own vQbits to gaiaftcl.xcode.vqbit.mac
//   • Exposes NATS connection state + mesh peer count for the HUD status dot
//   • Auto-reconnects after failure with 5-second backoff, cycling endpoints
//
// Architecture note: MeshBridge owns NATSClient (FusionCore) and speaks
// the GaiaFTCLCore vocabulary.  No SwiftUI dependencies — views observe via
// GaiaStackController which owns this bridge.
import Foundation
import FusionCore
import GaiaFTCLCore
import GaiaFTCLScene
import Observation

@Observable
@MainActor
final class MeshBridge {

    // ── Observable state ──────────────────────────────────────────────────

    var natsState: NATSClient.ConnectionState = .disconnected
    var peerCellIDs: Set<String>              = []
    var messagesReceived: Int                 = 0
    var meshKleinClosure: Float               = 1.0   // updated by inbound "closure" messages
    var currentEndpointIndex: Int             = 0

    var isConnected: Bool {
        if case .connected = natsState { return true }
        return false
    }

    // ── Internals ─────────────────────────────────────────────────────────

    private let endpoints = GuestNetworkDefaults.natsMeshEndpoints
    private var nats: NATSClient
    private var reconnecting = false

    private struct MeshClosurePayload: Codable {
        let cellID:       String
        let domain:       String
        let kleinClosure: Float
    }

    init() {
        let ep = GuestNetworkDefaults.natsMeshEndpoints[0]
        nats = NATSClient(host: ep.host, port: ep.port)
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────

    private var stateTask:   Task<Void, Never>?
    private var msgTask:     Task<Void, Never>?

    /// Connect to the mesh NATS broker and start feeding `store`.
    /// Tries all endpoints in round-robin order on failure.
    func start(feeding store: VQbitStore) {
        attachTasks(store: store)
        nats.connect()
        nats.subscribe(to: MeshSubjects.all)
    }

    /// Replace the NATSClient with the next endpoint and re-attach stream tasks.
    private func advanceAndReconnect(store: VQbitStore) {
        stateTask?.cancel()
        msgTask?.cancel()
        currentEndpointIndex = (currentEndpointIndex + 1) % endpoints.count
        let ep = endpoints[currentEndpointIndex]
        nats = NATSClient(host: ep.host, port: ep.port)
        attachTasks(store: store)
        nats.connect()
        nats.subscribe(to: MeshSubjects.all)
    }

    private func attachTasks(store: VQbitStore) {
        // Capture the specific NATSClient whose streams we will iterate —
        // this avoids re-reading self.nats after it has been swapped out.
        let client = nats

        stateTask = Task { [weak self] in
            guard let self else { return }
            for await state in client.stateStream {
                self.natsState = state
                if case .failed = state {
                    guard !self.reconnecting else { continue }
                    self.reconnecting = true
                    try? await Task.sleep(for: .seconds(5))
                    self.reconnecting = false
                    self.advanceAndReconnect(store: store)
                    return  // stale — advanceAndReconnect launched fresh tasks
                }
            }
        }

        msgTask = Task { [weak self] in
            guard let self else { return }
            for await msg in client.messages {
                self.messagesReceived += 1
                self.handle(msg, store: store)
            }
        }
    }

    // ── Publish ───────────────────────────────────────────────────────────

    /// Publish a local vQbit to the mesh so peer cells can consume it.
    func publish(_ vqbit: VQbit) {
        let payload = MeshVQbitPayload(from: vqbit, cellID: MeshSubjects.macCellID)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let subject = MeshSubjects.vqbit(
            domain: vqbit.domain.rawValue.lowercased(),
            cellID: MeshSubjects.macCellID
        )
        nats.publish(subject: subject, payload: data)
    }

    /// Publish control-plane text payloads (receipts, projection events) onto mesh subjects.
    func publishControl(subject: String, textPayload: String) {
        guard let data = textPayload.data(using: .utf8) else { return }
        nats.publish(subject: subject, payload: data)
    }

    // ── Inbound message handler ───────────────────────────────────────────

    private func handle(_ msg: NATSMessage, store: VQbitStore) {
        // Subject: gaiaftcl.<domain>.<type>.<cellID...>
        let parts = msg.subject.split(separator: ".", omittingEmptySubsequences: true)
        guard parts.count >= 4, parts[0] == "gaiaftcl" else { return }

        let msgType = String(parts[2])
        let cellID  = parts[3...].joined(separator: ".")

        // Track peer cell IDs seen on the mesh
        if cellID != MeshSubjects.macCellID {
            peerCellIDs.insert(cellID)
        }

        switch msgType {
        case "vqbit":
            handleVQbit(msg.payload, store: store)
        case "closure":
            handleClosure(msg.payload)
        case "scene":
            // USD scene bytes — phase 2: write to tmp, load via Entity(contentsOf:)
            break
        case "receipt":
            // Receipt chain entries — phase 2: verify + audit log
            break
        default:
            break
        }
    }

    private func handleVQbit(_ data: Data, store: VQbitStore) {
        guard let payload = try? JSONDecoder().decode(MeshVQbitPayload.self, from: data),
              let vqbit   = payload.toVQbit()
        else { return }
        store.ingest(vqbit)
    }

    private func handleClosure(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(MeshClosurePayload.self, from: data) else { return }
        meshKleinClosure = payload.kleinClosure
    }
}
