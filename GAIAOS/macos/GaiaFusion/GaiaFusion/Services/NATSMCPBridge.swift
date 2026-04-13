import Foundation
import Network

/// Sovereign NATS-bound MCP bridge — bidirectional comms for the Mac leaf cell:
/// - **In:** `PUB` JSON-RPC to `gaiaftcl.mcp.rx.<cell_wallet_id>` (`method` = tools below); response on `gaiaftcl.mcp.tx.<id>`.
/// - **Out:** presence ~12s + on-demand on `gaiaftcl.mcp.cell.presence.<id>`; discrete tuning on `gaiaftcl.mcp.cell.events.<id>`.
/// - **HTTP mirror:** `GET/POST /api/fusion/mcp-cell` / `mcp-cell/ping` on loopback for gateway/MCP without NATS.
@MainActor
final class NATSMCPBridge {
    private let natsURL: String
    private let cellWalletID: String
    private let workspaceRoot: URL
    private let onHotSwap: @MainActor () -> Void
    private let onActuatorCommand: @MainActor (_ method: String, _ params: [String: Any]?) -> String?

    private var connection: NWConnection?
    private var readTask: Task<Void, Never>?
    private var sidCounter: Int = 2000
    private var subBySid: [String: String] = [:]
    private var buffer = Data()
    private var hotSwapInFlight = false
    private let asmCompiler = WasmAssemblyQueue()

    private static let crlf = Data([0x0D, 0x0A])
    private static let maxPayload = 1_048_576

    var rxSubject: String { "gaiaftcl.mcp.rx.\(cellWalletID)" }
    var txSubject: String { "gaiaftcl.mcp.tx.\(cellWalletID)" }
    /// Mesh / gateway subscribers: periodic JSON — UI visibility + loopback port for MCP operator receipts.
    var presenceSubject: String { "gaiaftcl.mcp.cell.presence.\(cellWalletID)" }
    /// Discrete outbound events (dismiss, visibility flips, RPC acks) — optional subscribe for automation.
    var eventsSubject: String { "gaiaftcl.mcp.cell.events.\(cellWalletID)" }
    var anomaliesSubject: String { "gaiaftcl.language_game.anomalies" }

    /// True after CONNECT+SUB succeed and before `shutdown()`.
    private(set) var isArmed = false

    private var presenceTask: Task<Void, Never>?

    /// Extra fields merged into `presenceSubject` publishes (MainActor — reads coordinator / window state).
    private let presenceExtras: @MainActor () -> [String: Any]

    init(
        natsURL: String,
        cellWalletID: String,
        workspaceRoot: URL,
        onHotSwap: @escaping @MainActor () -> Void,
        onActuatorCommand: @escaping @MainActor (_ method: String, _ params: [String: Any]?) -> String?,
        presenceExtras: @escaping @MainActor () -> [String: Any]
    ) {
        self.natsURL = natsURL
        self.cellWalletID = cellWalletID
        self.workspaceRoot = workspaceRoot
        self.onHotSwap = onHotSwap
        self.onActuatorCommand = onActuatorCommand
        self.presenceExtras = presenceExtras
    }

    func armBridge() async -> Bool {
        guard let components = URLComponents(string: natsURL),
              let host = components.host
        else { return false }
        let portNumber = components.port ?? 4222
        guard let port = NWEndpoint.Port(rawValue: UInt16(portNumber)) else { return false }

        let c = NWConnection(host: .init(host), port: port, using: .tcp)
        let ready = await waitReady(c)
        guard ready else {
            c.cancel()
            return false
        }
        connection = c
        guard await sendFrame("CONNECT {\"verbose\":false,\"pedantic\":false,\"headers\":false}\r\n"),
              await subscribe(subject: rxSubject)
        else {
            c.cancel()
            connection = nil
            return false
        }
        readTask?.cancel()
        readTask = Task { [weak self] in
            await self?.readLoop()
        }
        isArmed = true
        startPresenceLoop()
        return true
    }

    /// Full presence JSON (same as periodic + on-demand pings). PUB to `presenceSubject`.
    func publishPresenceSnapshot(trigger: String) async {
        guard isArmed else { return }
        let payload = mergedPresencePayload(trigger: trigger)
        await publish(subject: presenceSubject, json: payload)
    }

    /// Lightweight outbound event on `eventsSubject` (tuning / automation trail).
    func publishCommsEvent(kind: String, fields: [String: Any] = [:]) async {
        guard isArmed else { return }
        var payload: [String: Any] = [
            "schema": "gaiaftcl_mcp_cell_event_v1",
            "kind": kind,
            "cell_wallet_id": cellWalletID,
            "ts_utc": ISO8601DateFormatter().string(from: Date()),
        ]
        for (k, v) in fields {
            payload[k] = v
        }
        await publish(subject: eventsSubject, json: payload)
    }

    private func mergedPresencePayload(trigger: String) -> [String: Any] {
        let extras = presenceExtras()
        var payload: [String: Any] = [
            "schema": "gaiaftcl_mcp_cell_presence_v1",
            "cell_wallet_id": cellWalletID,
            "mcp_rx_subject": rxSubject,
            "mcp_tx_subject": txSubject,
            "mcp_events_subject": eventsSubject,
            "trigger": trigger,
            "ts_utc": ISO8601DateFormatter().string(from: Date()),
        ]
        for (k, v) in extras {
            payload[k] = v
        }
        return payload
    }

    /// ~12s NATS heartbeats on `presenceSubject` so head/gateway/MCP can observe Mac cell visibility without HTTP.
    private func startPresenceLoop() {
        presenceTask?.cancel()
        presenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { break }
                await self.publishPresenceSnapshot(trigger: "periodic_heartbeat")
            }
        }
    }

    func shutdown() {
        presenceTask?.cancel()
        presenceTask = nil
        readTask?.cancel()
        readTask = nil
        connection?.cancel()
        connection = nil
        isArmed = false
    }

    func broadcastAnomaly(reason: String, stackTrace: String) async {
        let payload: [String: Any] = [
            "schema": "gaiaftcl_wasm_surface_fracture_v1",
            "cell_id": cellWalletID,
            "type": "WASM_SURFACE_FRACTURE",
            "reason": reason,
            "stack": stackTrace,
            "mcp_callback_topic": rxSubject,
            "ts_utc": ISO8601DateFormatter().string(from: Date()),
        ]
        await publish(subject: anomaliesSubject, json: payload)
    }

    private func waitReady(_ c: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            final class Probe: @unchecked Sendable {
                var done = false
                let cont: CheckedContinuation<Bool, Never>
                init(_ cont: CheckedContinuation<Bool, Never>) { self.cont = cont }
                func finish(_ value: Bool) {
                    guard !done else { return }
                    done = true
                    cont.resume(returning: value)
                }
            }
            let probe = Probe(continuation)
            c.stateUpdateHandler = { state in
                switch state {
                case .ready: probe.finish(true)
                case .failed(_), .waiting(_), .cancelled: probe.finish(false)
                default: break
                }
            }
            c.start(queue: DispatchQueue(label: "gaiaftcl.nats.mcp.bridge"))
        }
    }

    private func subscribe(subject: String) async -> Bool {
        sidCounter += 1
        let sid = String(sidCounter)
        subBySid[sid] = subject
        return await sendFrame("SUB \(subject) \(sid)\r\n")
    }

    private func sendFrame(_ frame: String) async -> Bool {
        guard let c = connection, let d = frame.data(using: .utf8) else { return false }
        return await withCheckedContinuation { continuation in
            c.send(content: d, completion: .contentProcessed { err in
                continuation.resume(returning: err == nil)
            })
        }
    }

    private func publish(subject: String, json: [String: Any]) async {
        guard let c = connection,
              let body = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        else { return }
        let header = "PUB \(subject) \(body.count)\r\n"
        guard let h = header.data(using: .utf8) else { return }
        let payload = h + body + Self.crlf
        _ = await withCheckedContinuation { continuation in
            c.send(content: payload, completion: .contentProcessed { err in
                continuation.resume(returning: err == nil)
            })
        }
    }

    private func readLoop() async {
        while !Task.isCancelled {
            guard let chunk = await receiveChunk(), !chunk.isEmpty else { continue }
            buffer.append(chunk)
            while let frame = parseFrame() {
                if case .message(_, let payload) = frame {
                    await handleMeshCommand(payload)
                }
            }
        }
    }

    private func receiveChunk() async -> Data? {
        guard let c = connection else { return nil }
        return await withCheckedContinuation { continuation in
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if error != nil { continuation.resume(returning: nil) }
                else { continuation.resume(returning: data) }
            }
        }
    }

    private enum Frame {
        case message(String, Data)
        case ping
        case ignored
    }

    private func parseFrame() -> Frame? {
        guard let eol = buffer.range(of: Self.crlf) else { return nil }
        let line = String(data: buffer.subdata(in: 0..<eol.lowerBound), encoding: .utf8) ?? ""
        let headerEnd = eol.upperBound
        if line == "PING" {
            buffer.removeSubrange(0..<headerEnd)
            Task { _ = await sendFrame("PONG\r\n") }
            return .ping
        }
        if line.hasPrefix("INFO") || line.hasPrefix("PONG") || line.hasPrefix("+OK") || line.hasPrefix("-ERR") {
            buffer.removeSubrange(0..<headerEnd)
            return .ignored
        }
        if !line.hasPrefix("MSG ") {
            buffer.removeSubrange(0..<headerEnd)
            return .ignored
        }
        let parts = line.split(separator: " ")
        guard parts.count >= 4, let payloadLen = Int(parts.last ?? "") else {
            buffer.removeSubrange(0..<headerEnd)
            return .ignored
        }
        guard payloadLen <= Self.maxPayload else {
            buffer.removeSubrange(0..<headerEnd)
            return .ignored
        }
        let totalNeeded = headerEnd + payloadLen + 2
        guard buffer.count >= totalNeeded else { return nil }
        let subject = String(parts[1])
        let payloadStart = headerEnd
        let payloadEnd = payloadStart + payloadLen
        let payload = buffer.subdata(in: payloadStart..<payloadEnd)
        buffer.removeSubrange(0..<totalNeeded)
        return .message(subject, payload)
    }

    private func handleMeshCommand(_ payload: Data) async {
        guard let req = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let method = req["method"] as? String,
              let rpcID = req["id"]
        else { return }

        let params = req["params"] as? [String: Any]
        let out: String
        switch method {
        case "read_mesh_source":
            out = executeRead(params: params)
        case "patch_mesh_source":
            out = executePatch(params: params)
        case "execute_wasm_pack":
            out = await executeWasmPack()
        case "hot_swap_viewport":
            if hotSwapInFlight {
                out = "[REFUSED] hot_swap_viewport already in flight"
            } else {
                hotSwapInFlight = true
                await MainActor.run { onHotSwap() }
                hotSwapInFlight = false
                out = "[CURE] Hot-swap executed. Viewport re-mounted."
            }
        case "set_mooring_variant", "set_plant_payload", "set_terminal_state", "set_heartbeat_sample", "set_receipt_hash", "set_epistemic_class", "set_measured_telemetry", "get_wasm_dom_probe", "get_ingestion_cycles":
            out = await MainActor.run {
                onActuatorCommand(method, params) ?? "[REFUSED] actuator command handler unavailable"
            }
        case "cell_presence_ping", "mcp_cell_snapshot":
            await publishPresenceSnapshot(trigger: "rpc_\(method)")
            await publishCommsEvent(kind: "rpc_\(method)", fields: ["jsonrpc_id": String(describing: rpcID)])
            let snap = mergedPresencePayload(trigger: "rpc_\(method)")
            if let data = try? JSONSerialization.data(withJSONObject: snap, options: [.sortedKeys]),
               let txt = String(data: data, encoding: .utf8) {
                out = txt
            } else {
                out = "{\"error\":\"presence_encode_failed\"}"
            }
        default:
            out = "[REFUSED] Unknown MCP tool requested by mesh."
        }
        await sendResponse(id: rpcID, content: out)
    }

    private func executeRead(params: [String: Any]?) -> String {
        guard let rel = params?["path"] as? String else {
            return "[REFUSED] read_mesh_source missing path"
        }
        let fileURL = workspaceRoot.appendingPathComponent(rel)
        guard fileURL.path.hasPrefix(workspaceRoot.path) else {
            return "[REFUSED] path outside workspace"
        }
        guard let txt = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return "[REFUSED] unable to read \(rel)"
        }
        return txt
    }

    private func executePatch(params: [String: Any]?) -> String {
        guard let rel = params?["path"] as? String,
              let content = params?["content"] as? String
        else { return "[REFUSED] patch_mesh_source requires path+content" }
        let fileURL = workspaceRoot.appendingPathComponent(rel)
        guard fileURL.path.hasPrefix(workspaceRoot.path) else {
            return "[REFUSED] path outside workspace"
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return "[CURE] Patched \(rel)"
        } catch {
            return "[REFUSED] patch failed: \(error.localizedDescription)"
        }
    }

    private func executeWasmPack() async -> String {
        let webDir = workspaceRoot.appendingPathComponent("services/gaiaos_ui_web").path
        do {
            let output = try await asmCompiler.dispatchCompilation(workingDirectory: webDir)
            return "[CURE] WASM compilation successful.\n\(output)"
        } catch {
            return "[REFUSED] Compilation failed. Mesh must formulate new patch.\n\(error.localizedDescription)"
        }
    }

    private func sendResponse(id: Any, content: String) async {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": ["content": [["type": "text", "text": content]]],
        ]
        await publish(subject: txSubject, json: response)
    }
}
