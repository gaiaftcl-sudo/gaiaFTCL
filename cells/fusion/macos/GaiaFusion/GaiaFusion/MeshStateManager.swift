import Foundation
import SwiftUI

@MainActor
final class MeshStateManager: ObservableObject {
    enum MutationPrecheckError: String, Sendable {
        case traceLayerInactive = "trace_layer_inactive"
        case missingExplicitTarget = "ERR_MISSING_EXPLICIT_TARGET"
        case unsupportedPlantKind = "unsupported_plant_kind"
        case quorumViolation = "quorum_violation"
    }
    private final class MeshStateTimer: @unchecked Sendable {
        private(set) var timer: Timer?

        func set(_ timer: Timer?) {
            self.timer = timer
        }

        func invalidate() {
            timer?.invalidate()
            timer = nil
        }
    }

    struct RuntimeCell: Equatable {
        let id: String
        let name: String
        let ipv4: String
        let role: String
    }

    struct Config {
        let heartbeatSeconds: TimeInterval
        let healthGateUrlFormat: String

        init(heartbeatSeconds: TimeInterval = 15.0, healthGateUrlFormat: String = "http://%@/health") {
            self.heartbeatSeconds = heartbeatSeconds
            self.healthGateUrlFormat = healthGateUrlFormat
        }
    }

    @Published private(set) var cells: [CellState] = []
    @Published private(set) var natsConnected: Bool = false
    @Published private(set) var vQbit: Double = 0.0
    @Published private(set) var lastNatsHeartbeatUtc: String = "never"
    @Published private(set) var natsCellTelemetry: [String: NATSCellTelemetry] = [:]
    @Published var bridgeReady: Bool = false

    struct NATSCellTelemetry: Equatable {
        let meshMoorOk: Bool?
        let longRunRunning: Bool?
        let gitSHA: String?
        let signalsTailHash: String?
        let tsUTC: String?
        let receivedAt: Date
    }

    /// Nine Hetzner/Netcup fleet hosts (WAN `8803/health`).
    private let fleetRuntimeCells: [RuntimeCell] = [
        .init(id: "gaiaftcl-hcloud-hel1-01", name: "gaiaftcl-hcloud-hel1-01", ipv4: "77.42.85.60", role: "head / gateway"),
        .init(id: "gaiaftcl-hcloud-hel1-02", name: "gaiaftcl-hcloud-hel1-02", ipv4: "135.181.88.134", role: "Franklin"),
        .init(id: "gaiaftcl-hcloud-hel1-03", name: "gaiaftcl-hcloud-hel1-03", ipv4: "77.42.32.156", role: "Fara"),
        .init(id: "gaiaftcl-hcloud-hel1-04", name: "gaiaftcl-hcloud-hel1-04", ipv4: "77.42.88.110", role: "mesh"),
        .init(id: "gaiaftcl-hcloud-hel1-05", name: "gaiaftcl-hcloud-hel1-05", ipv4: "37.27.7.9", role: "mesh"),
        .init(id: "gaiaftcl-netcup-nbg1-01", name: "gaiaftcl-netcup-nbg1-01", ipv4: "37.120.187.247", role: "Netcup"),
        .init(id: "gaiaftcl-netcup-nbg1-02", name: "gaiaftcl-netcup-nbg1-02", ipv4: "152.53.91.220", role: "Netcup"),
        .init(id: "gaiaftcl-netcup-nbg1-03", name: "gaiaftcl-netcup-nbg1-03", ipv4: "152.53.88.141", role: "Netcup"),
        .init(id: "gaiaftcl-netcup-nbg1-04", name: "gaiaftcl-netcup-nbg1-04", ipv4: "37.120.187.174", role: "Netcup"),
    ]

    /// Local GaiaFusion leaf — probed on loopback `/api/fusion/health` so `vQbit` uses a **10-node** mesh (9 fleet + Mac).
    private static let macFusionLeafRuntime = RuntimeCell(
        id: "gaiaftcl-mac-fusion-leaf",
        name: "gaiaftcl-mac-fusion-leaf",
        ipv4: "127.0.0.1",
        role: "Mac leaf / GaiaFusion"
    )

    enum MeshConstants {
        static let fleetNodeCount = 9
        static let meshNodeCount = fleetNodeCount + 1
        static let macFusionLeafId = "gaiaftcl-mac-fusion-leaf"
    }

    @Published private(set) var recentSwaps: [SwapState] = []

    private let config: Config
    private let timerBox = MeshStateTimer()
    private let natsFormatter = ISO8601DateFormatter()
    private var natsStreamConnected = false

    init(config: Config = MeshStateManager.Config()) {
        let configuredHeartbeat = TimeInterval(UserDefaults.standard.integer(forKey: "fusion_heartbeat_seconds"))
        let finalHeartbeat = configuredHeartbeat > 0 ? configuredHeartbeat : config.heartbeatSeconds
        self.config = Config(heartbeatSeconds: finalHeartbeat, healthGateUrlFormat: config.healthGateUrlFormat)
        let fleet = fleetRuntimeCells.map {
            CellState(
                id: $0.id,
                name: $0.name,
                ipv4: $0.ipv4,
                role: $0.role,
                health: 0.0,
                status: "unknown",
                inputPlantType: .unknown,
                outputPlantType: .unknown,
                active: false
            )
        }
        let macLeaf = CellState(
            id: Self.macFusionLeafRuntime.id,
            name: Self.macFusionLeafRuntime.name,
            ipv4: Self.macFusionLeafRuntime.ipv4,
            role: Self.macFusionLeafRuntime.role,
            health: 0.0,
            status: "unknown",
            inputPlantType: .unknown,
            outputPlantType: .unknown,
            active: false
        )
        self.cells = fleet + [macLeaf]
    }

    deinit {
        timerBox.invalidate()
    }

    var healthyCount: Int {
        cells.filter { $0.active && $0.health >= 0.25 }.count
    }

    var meshHealthText: String {
        "\(healthyCount)/\(cells.count)"
    }

    func start() {
        Task { [weak self] in
            await self?.refresh()
        }
        timerBox.invalidate()
        timerBox.set(
            Timer.scheduledTimer(withTimeInterval: config.heartbeatSeconds, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.refresh()
            }
        }
        )
    }

    func stop() {
        timerBox.invalidate()
    }

    func refresh() async {
        await refreshCells()
    }

    func canSwap() -> Bool {
        healthyCount >= 5
    }

    func precheckSwap(
        traceActive: Bool,
        cellID: String?,
        input: String,
        output: String
    ) -> MutationPrecheckError? {
        guard traceActive else {
            return .traceLayerInactive
        }
        guard let cellID, !cellID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingExplicitTarget
        }
        guard canSwap() else {
            return .quorumViolation
        }
        let normalizedInput = PlantType.normalized(raw: input)
        let normalizedOutput = PlantType.normalized(raw: output)
        guard normalizedInput != .unknown, normalizedOutput != .unknown else {
            return .unsupportedPlantKind
        }
        return nil
    }

    func precheckTraceForMutation(traceActive: Bool) -> MutationPrecheckError? {
        traceActive ? nil : .traceLayerInactive
    }

    func swapHistory() -> [SwapState] {
        recentSwaps
    }

    func requestSwap(cellID: String, input: String, output: String) -> (success: Bool, requestID: String, message: String) {
        guard canSwap() else {
            return (false, "", "quorum_violation")
        }
        let normalizedInput = PlantType.normalized(raw: input)
        let normalizedOutput = PlantType.normalized(raw: output)
        guard normalizedInput != .unknown, normalizedOutput != .unknown else {
            return (false, "", "unsupported_plant_kind")
        }

        let requestID = UUID().uuidString
        let iso = ISO8601DateFormatter().string(from: Date())
        var swap = SwapState(
            requestID: requestID,
            cellID: cellID,
            inputPlantType: normalizedInput.rawValue,
            outputPlantType: normalizedOutput.rawValue,
            createdAtUtc: iso,
            lifecycle: .requested,
            detail: "local lifecycle started"
        )
        swap.advance()
        swap.advance()
        swap.advance()
        recentSwaps.insert(swap, at: 0)
        if recentSwaps.count > 10 {
            recentSwaps.removeLast(recentSwaps.count - 10)
        }
        return (true, requestID, "swap_requested")
    }

    func projectionPayload() -> ProjectionState {
        let iso = ISO8601DateFormatter().string(from: Date())
        return ProjectionState(
            meshHealthy: healthyCount,
            meshTotal: cells.count,
            natsConnected: natsConnected,
            vqbitDelta: vQbit,
            lastUpdatedUtc: iso,
            swapsRecent: recentSwaps
        )
    }

    func recordNATSCellStatus(subject: String, payload: [String: Any], receivedAt: Date = Date()) {
        _ = subject
        let cellID = payload["cell_id"] as? String
        let meshMoorOk = payload["mesh_moor_ok"] as? Bool
        let longRunRunning = payload["long_run_running"] as? Bool
        let gitSHA = payload["git_sha"] as? String
        let signalsTailHash = payload["signals_tail_hash"] as? String
        let tsUTC = payload["ts_utc"] as? String

        let heartbeat = natsFormatter.date(from: tsUTC ?? "") ?? receivedAt
        lastNatsHeartbeatUtc = natsFormatter.string(from: heartbeat)

        if let cellID {
            natsCellTelemetry[cellID] = NATSCellTelemetry(
                meshMoorOk: meshMoorOk,
                longRunRunning: longRunRunning,
                gitSHA: gitSHA,
                signalsTailHash: signalsTailHash,
                tsUTC: tsUTC,
                receivedAt: heartbeat
            )
        }

        natsStreamConnected = true
        natsConnected = natsStreamConnected || cells.contains { $0.active }
    }

    private func refreshCells() async {
        var next: [CellState] = []
        var offlineFleet: [RuntimeCell] = []
        for cell in fleetRuntimeCells {
            let updated = await probeFleetCell(cell)
            next.append(updated)
            if !updated.active {
                offlineFleet.append(cell)
            }
        }
        next.append(await probeMacFusionLeaf())
        await MainActor.run {
            cells = next
            let nowHealthy = Double(healthyCount)
            vQbit = nowHealthy / Double(max(1, cells.count))
            let hasActiveCell = cells.contains { $0.active }
            natsConnected = natsStreamConnected || hasActiveCell
        }
        await maybeRemediateFleet(offending: offlineFleet)
    }

    /// When preferences allow, SSH to **offline** fleet cells and restart the gateway stack (`:8803` surface).
    /// Cooldown per cell (default 10 min) avoids hammering `docker compose` during WAN blips.
    private func maybeRemediateFleet(offending: [RuntimeCell]) async {
        guard UserDefaults.standard.bool(forKey: "fusion_mesh_heal_enabled") else { return }
        guard let keyPath = UserDefaults.standard.string(forKey: "fusion_ssh_key_path"),
              !keyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.isReadableFile(atPath: keyPath)
        else {
            return
        }
        guard !offending.isEmpty else { return }
        let user = UserDefaults.standard.string(forKey: "fusion_ssh_user") ?? "root"
        let now = Date().timeIntervalSince1970
        let cooldown: TimeInterval = 600
        // Best-effort: compose project on cell + restart published :8803 container(s).
        let remote = """
        set -e
        if [ -d /opt/gaia/GAIAOS ]; then
          cd /opt/gaia/GAIAOS && docker compose up -d --no-build 2>/dev/null || true
        fi
        for id in $(docker ps -aq --filter publish=8803 2>/dev/null); do
          docker restart "$id" 2>/dev/null || true
        done
        exit 0
        """
        for cell in offending {
            let key = "fusion_mesh_heal_ts_\(cell.id)"
            let last = UserDefaults.standard.double(forKey: key)
            if last > 0, now - last < cooldown {
                continue
            }
            let code = await runFleetSSH(host: cell.ipv4, keyPath: keyPath, user: user, remoteScript: remote)
            if code == 0 {
                UserDefaults.standard.set(now, forKey: key)
                print("[mesh heal] ssh remediation sent: \(cell.name) \(cell.ipv4)")
                fflush(stdout)
            }
        }
    }

    private func runFleetSSH(host: String, keyPath: String, user: String, remoteScript: String) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=14",
                    "-i", keyPath,
                    "\(user)@\(host)",
                    remoteScript,
                ]
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: 127)
                }
            }
        }
    }

    /// Bound port for `LocalServer` /api/fusion/health (UserDefaults `fusion_ui_port`, default 8910).
    private func localFusionHealthPort() -> Int {
        let configured = UserDefaults.standard.integer(forKey: "fusion_ui_port")
        if configured > 0, configured <= 65_535 {
            return configured
        }
        return 8910
    }

    private func probeMacFusionLeaf() async -> CellState {
        let cell = Self.macFusionLeafRuntime
        let port = localFusionHealthPort()
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/fusion/health") else {
            return makeOfflineCell(cell)
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let responseHTTP = response as? HTTPURLResponse else {
                return makeOfflineCell(cell)
            }
            let status = responseHTTP.statusCode
            guard (200 ... 399).contains(status) else {
                return makeOfflineCell(cell)
            }
            if let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let statusText = doc["status"] as? String,
               statusText == "ok" {
                return CellState(
                    id: cell.id,
                    name: cell.name,
                    ipv4: cell.ipv4,
                    role: cell.role,
                    health: 1.0,
                    status: "ok",
                    inputPlantType: .unknown,
                    outputPlantType: .unknown,
                    active: true
                )
            }
            return makeOfflineCell(cell)
        } catch {
            return makeOfflineCell(cell)
        }
    }

    private func probeFleetCell(_ cell: RuntimeCell) async -> CellState {
        guard let url = URL(string: "http://\(cell.ipv4):8803/health"),
              !cell.ipv4.isEmpty
        else {
            return makeOfflineCell(cell)
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let responseHTTP = response as? HTTPURLResponse else {
                return makeOfflineCell(cell)
            }
            let status = responseHTTP.statusCode
            guard (200...399).contains(status) else {
                return makeOfflineCell(cell)
            }
            if let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let statusText = doc["status"] as? String {
                return CellState(
                    id: cell.id,
                    name: cell.name,
                    ipv4: cell.ipv4,
                    role: cell.role,
                    health: 1.0,
                    status: statusText,
                    inputPlantType: parsePlant(doc["input_plant_type"]),
                    outputPlantType: parsePlant(doc["output_plant_type"]),
                    active: true
                )
            }
            return CellState(
                id: cell.id,
                name: cell.name,
                ipv4: cell.ipv4,
                role: cell.role,
                health: status == 200 ? 1.0 : 0.0,
                status: status == 200 ? "ok" : "error",
                inputPlantType: .unknown,
                outputPlantType: .unknown,
                active: status == 200
            )
        } catch {
            return makeOfflineCell(cell)
        }
    }

    private func parsePlant(_ raw: Any?) -> PlantType {
        guard let str = raw as? String else {
            return .unknown
        }
        return PlantType.normalized(raw: str)
    }

    private func makeOfflineCell(_ cell: RuntimeCell) -> CellState {
        CellState(
            id: cell.id,
            name: cell.name,
            ipv4: cell.ipv4,
            role: cell.role,
            health: 0.0,
            status: "offline",
            inputPlantType: .unknown,
            outputPlantType: .unknown,
            active: false
        )
    }
}
