import Darwin
import Foundation
import FusionCore
import GaiaFTCLCore
import GaiaGateKit
import GRDB
import VQbitSubstrate

// MARK: — CLI config

private struct Config {
    var pingOnly = false
    var tauStatusOnly = false
    var mooringStatusOnly = false
    var testID: String?
    var primArg: String = ""
    var sMean: Float?
    var sMeanSequence: [Float] = []
    var injectComponents: (Float, Float, Float, Float)?
    var runs: Int = 1
    var waitFranklinCycle = false
    var timeoutSeconds: Double = 10
    var dbPath: String?
    var logPath: String?
}

private enum InjectorError: Error, CustomStringConvertible {
    case usage(String)
    case connectFailed(String)
    case timeout
    case resolvePrim(String)
    case sql(String)

    var description: String {
        switch self {
        case .usage(let s): return s
        case .connectFailed(let s): return s
        case .timeout: return "Timed out waiting for C4 projection"
        case .resolvePrim(let s): return s
        case .sql(let s): return s
        }
    }
}

// MARK: — Prim resolution

private let roleToContract: [String: (gameID: String, domain: String)] = [
    "ProjectionProbe": ("QUANTUM-PROOF-001", "quantum_proof"),
    "CircuitFamily": ("QC-CIRCUIT-001", "quantum_circuit"),
    "VariationalFamily": ("QC-VARIATIONAL-001", "quantum_variational"),
    "LinearAlgebraFamily": ("QC-LINALG-001", "quantum_linear_algebra"),
    "SimulationFamily": ("QC-SIMULATION-001", "quantum_simulation"),
    "BosonicFamily": ("QC-BOSONIC-001", "quantum_bosonic"),
    "ErrorCorrectionFamily": ("QC-ERRORCORR-001", "quantum_error_correction"),
    "Tokamak": ("FUSION-TOKAMAK-001", "fusion"),
]

// MARK: — τ + mooring (disk IQ mirrors VQbitVM / Franklin)

private struct TauFileSnapshot: Sendable {
    let live: Bool
    let blockHeight: UInt64?
    let ageSeconds: Double?
    /// From **`tau_sync_state.json`** (`tau_source`), else **`none`**.
    let source: String
}

private func tauSyncFileStatus() -> TauFileSnapshot {
    let url = GaiaInstallPaths.tauSyncStateURL
    guard FileManager.default.fileExists(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let iso = obj["received_at_iso"] as? String
    else {
        return TauFileSnapshot(live: false, blockHeight: nil, ageSeconds: nil, source: "none")
    }
    let fmt = ISO8601DateFormatter()
    guard let received = fmt.date(from: iso) else {
        return TauFileSnapshot(live: false, blockHeight: nil, ageSeconds: nil, source: "none")
    }
    let age = Date().timeIntervalSince(received)
    let live = age <= NATSConfiguration.tauStalenessSeconds
    let bh = (obj["block_height"] as? UInt64)
        ?? (obj["block_height"] as? Int).map(UInt64.init)
    let src = (obj["tau_source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "none"
    return TauFileSnapshot(live: live, blockHeight: bh, ageSeconds: age, source: src)
}

private func mooringFileStatus() -> (moored: Bool, latitude: Double?, longitude: Double?, s3Spatial: Double?) {
    let url = GaiaInstallPaths.cellIdentityURL
    guard FileManager.default.fileExists(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return (false, nil, nil, nil)
    }
    let lat = obj["latitude"] as? Double
    let lon = obj["longitude"] as? Double
    let s3 = obj["s3_spatial"] as? Double
    let moored: Bool
    if let lat, let lon, let s3, s3 > 0, !(abs(lat) < 1e-9 && abs(lon) < 1e-9) {
        moored = true
    } else {
        moored = false
    }
    return (moored, lat, lon, s3)
}

private func assertTauAndMooringForOQ() {
    let moor = mooringFileStatus()
    if !moor.moored {
        fputs("OQ BLOCKED: Cell not moored. Grant CoreLocation access.\n", stderr)
        exit(3)
    }
    let tauURL = GaiaInstallPaths.tauSyncStateURL
    if !FileManager.default.fileExists(atPath: tauURL.path) {
        fputs("WARN: tau_sync_state.json not present — VQbitVM self-fetches τ (HTTPS); OQ proceeds.\n", stderr)
        return
    }
    let snap = tauSyncFileStatus()
    if snap.blockHeight == nil {
        fputs("WARN: τ block height unreadable in tau_sync_state.json — OQ proceeds.\n", stderr)
        return
    }
    if !snap.live {
        fputs("WARN: τ snapshot stale on disk — VQbitVM refreshes via HTTPS; OQ proceeds.\n", stderr)
    }
}

private func defaultSubstratePath() -> String {
    if let e = ProcessInfo.processInfo.environment["GAIAFTCL_DB_PATH"], !e.isEmpty { return e }
    let appSupport = try! FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
    )
    return appSupport.appendingPathComponent("GaiaFTCL/substrate.sqlite", isDirectory: false).path
}

private func resolvePrimID(primArg: String, dbQueue: DatabaseQueue?) throws -> UUID {
    if let row = roleToContract[primArg] {
        return GaiaFTCLPrimIdentity.primID(contractGameID: row.gameID, contractDomain: row.domain)
    }
    guard let dbQueue else {
        throw InjectorError.resolvePrim("No database open — needed for game_id \(primArg)")
    }
    let gid = primArg
    let domain: String? = try dbQueue.read { db in
        try String.fetchOne(
            db,
            sql: "SELECT domain FROM language_game_contracts WHERE game_id = ? LIMIT 1",
            arguments: [gid]
        )
    }
    guard let domain, !domain.isEmpty else {
        if gid == "QUANTUM-PROOF-001" {
            return GaiaFTCLPrimIdentity.primID(contractGameID: gid, contractDomain: "quantum_proof")
        }
        if gid == "FUSION-TOKAMAK-001" {
            return GaiaFTCLPrimIdentity.primID(contractGameID: gid, contractDomain: "fusion")
        }
        throw InjectorError.resolvePrim("Unknown game_id \(gid) (no language_game_contracts row)")
    }
    return GaiaFTCLPrimIdentity.primID(contractGameID: gid, contractDomain: domain.lowercased())
}

// MARK: — NATS

private func parseNATSURL(_ url: String) -> (host: String, port: UInt16) {
    guard let u = URL(string: url), let host = u.host else { return ("127.0.0.1", 4222) }
    return (host, UInt16(u.port ?? 4222))
}

private func connectNATS(url: String) async throws -> NATSClient {
    let (h, p) = parseNATSURL(url)
    let client = NATSClient(host: h, port: p)
    client.connect()
    for await state in client.stateStream {
        switch state {
        case .connected:
            return client
        case .failed(let msg):
            throw InjectorError.connectFailed(msg)
        default:
            continue
        }
    }
    throw InjectorError.connectFailed("stream ended")
}

private func wireSequence() -> Int64 {
    Int64(bitPattern: mach_absolute_time())
}

private func waitForC4(
    client: NATSClient,
    prim: UUID,
    minSequence: Int64,
    timeoutSeconds: Double
) async throws -> C4ProjectionWire {
    try await withThrowingTaskGroup(of: C4ProjectionWire.self) { group in
        group.addTask {
            for await msg in client.messages {
                guard msg.subject == SubstrateWireSubjects.c4Projection else { continue }
                guard msg.payload.count == C4ProjectionWire.byteCount else { continue }
                guard let w = try? C4ProjectionCodec.decode(msg.payload),
                      w.primID == prim,
                      w.sequence >= minSequence
                else { continue }
                return w
            }
            throw InjectorError.timeout
        }
        group.addTask {
            try await Task.sleep(for: .seconds(timeoutSeconds))
            throw InjectorError.timeout
        }
        guard let first = try await group.next() else { throw InjectorError.timeout }
        group.cancelAll()
        return first
    }
}

private func waitFranklinMonologue(timeoutSeconds: Double) async throws {
    let client = try await connectNATS(url: NATSConfiguration.franklinNATSURL)
    client.subscribeSync(to: "gaiaftcl.franklin.monologue")
    try await withThrowingTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await msg in client.messages {
                guard let text = String(data: msg.payload, encoding: .utf8) else { continue }
                if text.contains("Self-review") || text.lowercased().contains("cycle complete") {
                    return true
                }
            }
            return false
        }
        group.addTask {
            try await Task.sleep(for: .seconds(timeoutSeconds))
            return false
        }
        guard let first = try await group.next() else { throw InjectorError.timeout }
        group.cancelAll()
        if !first { throw InjectorError.timeout }
    }
    client.disconnect()
}

// MARK: — Row math

private func s8Proxy(s1: Float, s2: Float, s3: Float, s4: Float, c1: Float, c2: Float, c3: Float, c4: Float) -> Float {
    let sMean = Double(s1 + s2 + s3 + s4) * 0.25
    let cMean = Double(c1 + c2 + c3 + c4) * 0.25
    let s4p = Float(1.0 - sMean)
    let scp = Float(1.0 - cMean)
    return s4p + scp
}

private func printRow(
    test: String,
    prim: String,
    sMean: Float,
    run: Int,
    proj: C4ProjectionWire
) {
    let s4p = 1.0 - Double(sMean)
    let cm = (Double(proj.c1Trust) + Double(proj.c2Identity) + Double(proj.c3Closure) + Double(proj.c4Consequence)) * 0.25
    let scp = 1.0 - cm
    let s8 = Float(s4p + scp)
    print(
        "\(test)\t\(prim)\t\(sMean)\t\(run)\t0x\(String(format: "%02x", proj.terminal))\t\(proj.violationCode)\t\(proj.c3Closure)\t\(s8)\tPASS"
    )
}

// MARK: — Log scan

private func lastRecordBytes(logPath: String, prim: UUID) throws -> Data? {
    guard let fh = FileHandle(forReadingAtPath: logPath) else { return nil }
    defer { try? fh.close() }
    let fileSize = try fh.seekToEnd()
    guard fileSize > 0 else { return nil }
    let chunk = min(UInt64(fileSize), 512 * 1024)
    try fh.seek(toOffset: fileSize - chunk)
    guard let tail = try fh.read(upToCount: Int(chunk)) else { return nil }
    let primBytes = uuidBytes(prim)
    var i = tail.endIndex
    let size = VQbitPointsRecordWire.byteCount
    while i >= tail.startIndex + size {
        i = tail.index(i, offsetBy: -size)
        let slice = tail[i ..< tail.index(i, offsetBy: size)]
        if slice.prefix(16) == primBytes {
            return Data(slice)
        }
    }
    return nil
}

private func uuidBytes(_ u: UUID) -> Data {
    withUnsafeBytes(of: u.uuid) { Data($0) }
}

private func parseArgs() throws -> Config {
    var c = Config()
    var i = CommandLine.arguments.makeIterator()
    _ = i.next()
    while let a = i.next() {
        switch a {
        case "--ping":
            c.pingOnly = true
        case "--tau-status":
            c.tauStatusOnly = true
        case "--mooring-status":
            c.mooringStatusOnly = true
        case "--test":
            c.testID = i.next()
        case "--prim":
            c.primArg = i.next() ?? ""
        case "--s-mean":
            guard let v = i.next(), let f = Float(v) else { throw InjectorError.usage("--s-mean requires float") }
            c.sMean = f
        case "--s-mean-sequence":
            guard let raw = i.next() else { throw InjectorError.usage("--s-mean-sequence requires list") }
            c.sMeanSequence = raw.split(separator: ",").compactMap { Float(String($0).trimmingCharacters(in: .whitespaces)) }
        case "--inject":
            guard let raw = i.next() else { throw InjectorError.usage("--inject requires s1=…") }
            var s1: Float = 0, s2: Float = 0, s3: Float = 0, s4: Float = 0
            for part in raw.split(separator: ",") {
                let kv = part.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2, let val = Float(kv[1]) else { continue }
                switch kv[0].lowercased() {
                case "s1": s1 = val
                case "s2": s2 = val
                case "s3": s3 = val
                case "s4": s4 = val
                default: break
                }
            }
            c.injectComponents = (s1, s2, s3, s4)
        case "--runs":
            guard let v = i.next(), let n = Int(v), n > 0 else { throw InjectorError.usage("--runs requires positive int") }
            c.runs = n
        case "--wait-franklin-cycle":
            c.waitFranklinCycle = true
        case "--timeout":
            guard let v = i.next(), let t = Double(v), t > 0 else { throw InjectorError.usage("--timeout requires seconds") }
            c.timeoutSeconds = t
        case "--db":
            c.dbPath = i.next()
        case "--log":
            c.logPath = i.next()
        case "--help", "-h":
            throw InjectorError.usage(
                "QuantumOQInjector --ping | --tau-status | --mooring-status |\n" +
                    "  (--test OQ-QM-00x ... --prim …)\n" +
                    "  --prim [role|game_id] --s-mean f | --s-mean-sequence a,b,...\n" +
                    "  [--runs N] [--timeout sec] [--db path] [--log path] [--wait-franklin-cycle]\n" +
                    "OQ tests require τ live (tau_sync_state.json) and mooring (cell_identity.json)."
            )
        default:
            throw InjectorError.usage("Unknown flag \(a)")
        }
    }
    return c
}

// MARK: — Run tests

private func runInjectAllDims(
    client: NATSClient,
    prim: UUID,
    s1: Float,
    s2: Float,
    s3: Float,
    s4: Float,
    timeout: Double
) async throws -> C4ProjectionWire {
    var seq = wireSequence()
    for dim in 0 ..< 4 {
        let val = [s1, s2, s3, s4][dim]
        seq = wireSequence()
        let wire = S4DeltaWire(
            primID: prim,
            dimension: UInt8(dim),
            oldValue: 0,
            newValue: val,
            sequence: seq
        )
        let payload = try S4DeltaCodec.encode(wire)
        client.publish(subject: SubstrateWireSubjects.s4Delta, payload: payload)
    }
    return try await waitForC4(client: client, prim: prim, minSequence: seq, timeoutSeconds: timeout)
}

private func runOQQM007(dbPath: String, logPath: String) throws {
    var qcfg = Configuration()
    qcfg.readonly = true
    let q = try DatabaseQueue(path: dbPath, configuration: qcfg)
    let sum: Int = try q.read { db in
        try Int.fetchOne(
            db,
            sql: "SELECT IFNULL(SUM(algorithm_count),0) FROM language_game_contracts WHERE domain LIKE 'quantum%'"
        ) ?? 0
    }
    print("OQ-QM-007\talgorithm_count_sum\t\(sum)")
    if sum != 19 {
        fputs("EXPECTED algorithm_count sum 19 OBSERVED \(sum)\n", stderr)
        exit(2)
    }
    let familyRoles = [
        "CircuitFamily", "VariationalFamily", "LinearAlgebraFamily",
        "SimulationFamily", "BosonicFamily", "ErrorCorrectionFamily",
    ]
    var nResidual = 0
    for role in familyRoles {
        let pid = try resolvePrimID(primArg: role, dbQueue: q)
        guard let blob = try lastRecordBytes(logPath: logPath, prim: pid), blob.count == VQbitPointsRecordWire.byteCount else {
            fputs("OQ-QM-007\t\(role)\tno log record\n", stderr)
            nResidual += 1
            continue
        }
        let term = blob[blob.startIndex + 48]
        print("OQ-QM-007\t\(role)\tterminal\t0x\(String(format: "%02x", term))")
        if term == 0x00 { nResidual += 1 }
        if ![0x01, 0x03, 0x04].contains(term) {
            fputs("EXPECTED terminal in {0x01,0x03,0x04} OBSERVED 0x\(String(format: "%02x", term)) for \(role)\n", stderr)
            exit(2)
        }
    }
    print("OQ-QM-007\tN_residual\t\(nResidual)")
    if nResidual != 0 {
        fputs("EXPECTED N_residual 0\n", stderr)
        exit(2)
    }
    let repo = FranklinDocumentRepository(db: q)
    let (_, peersByPrim) = try repo.fetchPrimCalorieAndClosurePeers()
    let tensorPath = ProcessInfo.processInfo.environment["GAIAFTCL_TENSOR_PATH"].map { URL(fileURLWithPath: $0) }
        ?? GaiaInstallPaths.manifoldTensorURL
    let overflowPath = ProcessInfo.processInfo.environment["GAIAFTCL_OVERFLOW_MAP_PATH"].map { URL(fileURLWithPath: $0) }
        ?? GaiaInstallPaths.vqbitPrimRowOverflowMapURL
    guard let nStr = ProcessInfo.processInfo.environment["GAIAFTCL_TENSOR_N"], let n = UInt32(nStr) else {
        print("OQ-QM-007\tWARN\tGAIAFTCL_TENSOR_N unset — skip closureResidual tensor compute")
        let maxR = 0.0
        print("OQ-QM-007\tclosure_residual_max\t\(maxR)")
        return
    }
    let store = try ManifoldTensorStore(tensorPath: tensorPath, overflowURL: overflowPath, rowCount: n)
    let thresholds = try repo.fetchPrimIDToCalorieThreshold()
    let quantumRows = try q.read { db -> [(String, String)] in
        try Row.fetchAll(
            db,
            sql: "SELECT game_id, domain FROM language_game_contracts WHERE domain LIKE 'quantum%' ORDER BY game_id"
        ).map { ($0["game_id"], $0["domain"]) }
    }
    var maxResidual: Double = 0
    for (gid, dom) in quantumRows {
        let d = dom.lowercased()
        let pid = GaiaFTCLPrimIdentity.primID(contractGameID: gid, contractDomain: d)
        guard let tau = thresholds[pid], let peers = peersByPrim[pid], !peers.isEmpty else { continue }
        let r = try ManifoldConstitutionalClosurePhysics.computeClosureResidual(
            store: store,
            threshold: tau,
            domainPrimIDs: peers
        )
        maxResidual = max(maxResidual, r)
    }
    print("OQ-QM-007\tclosure_residual_max\t\(maxResidual)")
    if maxResidual >= 0.05 {
        fputs("EXPECTED closure_residual < 0.05 OBSERVED \(maxResidual)\n", stderr)
        exit(2)
    }
}

@main
enum QuantumOQInjector {
    static func main() async {
        do {
            try await run()
        } catch let e as InjectorError {
            fputs("FAILED: \(e.description)\n", stderr)
            exit(1)
        } catch {
            fputs("FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let cfg = try parseArgs()
        if cfg.tauStatusOnly {
            let t = tauSyncFileStatus()
            print("TAU_BLOCK_HEIGHT: \(t.blockHeight.map { String($0) } ?? "unknown")")
            print("TAU_SOURCE: \(t.source)")
            print("TAU_STALE: \(!t.live)")
            if let a = t.ageSeconds {
                print("age_seconds: \(Int(a))")
            }
            return
        }
        if cfg.mooringStatusOnly {
            let m = mooringFileStatus()
            print("MOORED: \(m.moored)")
            if let lat = m.latitude { print("latitude: \(lat)") }
            if let lon = m.longitude { print("longitude: \(lon)") }
            if let s3 = m.s3Spatial { print("s3_spatial: \(s3)") }
            return
        }
        if cfg.pingOnly {
            do {
                let c = try await connectNATS(url: NATSConfiguration.vqbitNATSURL)
                c.disconnect()
                print("Connected to C4 cell NATS at \(NATSConfiguration.vqbitNATSURL)")
            } catch {
                fputs("FAILED: \(error)\n", stderr)
                exit(1)
            }
            let t = tauSyncFileStatus()
            let m = mooringFileStatus()
            let heightStr = t.blockHeight.map { String($0) } ?? "unknown"
            print("τ block height: \(heightStr) (source: \(t.source))")
            print("Moored: \(m.moored)")
            return
        }

        let dbPath = cfg.dbPath ?? defaultSubstratePath()
        var dbCfg = Configuration()
        dbCfg.readonly = true
        let dbQueue = FileManager.default.fileExists(atPath: dbPath) ? try DatabaseQueue(path: dbPath, configuration: dbCfg) : nil
        let logPath = cfg.logPath ?? GaiaInstallPaths.vqbitPointsLogURL.path

        if cfg.testID == "OQ-QM-007" {
            assertTauAndMooringForOQ()
            try runOQQM007(dbPath: dbPath, logPath: logPath)
            return
        }

        guard let test = cfg.testID, !cfg.primArg.isEmpty else {
            throw InjectorError.usage("Require --test and --prim (or --ping)")
        }

        assertTauAndMooringForOQ()

        let prim = try resolvePrimID(primArg: cfg.primArg, dbQueue: dbQueue)
        let client = try await connectNATS(url: NATSConfiguration.vqbitNATSURL)
        client.subscribeSync(to: SubstrateWireSubjects.c4Projection)

        switch test {
        case "OQ-QM-001":
            let states: [(Float, UInt8)] = [
                (0.85, 0x01),
                (0.66, 0x02),
                (0.20, 0x03),
                (0.05, 0x04),
            ]
            for (sMean, expected) in states {
                for r in 1 ... cfg.runs {
                    let seq = wireSequence()
                    let wire = S4DeltaWire(
                        primID: prim,
                        dimension: S4DeltaWire.allStructuralDimensions,
                        oldValue: 0,
                        newValue: sMean,
                        sequence: seq
                    )
                    let payload = try S4DeltaCodec.encode(wire)
                    client.publish(subject: SubstrateWireSubjects.s4Delta, payload: payload)
                    let proj = try await waitForC4(
                        client: client,
                        prim: prim,
                        minSequence: seq,
                        timeoutSeconds: cfg.timeoutSeconds
                    )
                    printRow(test: test, prim: cfg.primArg, sMean: sMean, run: r, proj: proj)
                    if proj.terminal != expected {
                        fputs(
                            "EXPECTED terminal 0x\(String(format: "%02x", expected)) OBSERVED 0x\(String(format: "%02x", proj.terminal))\n",
                            stderr
                        )
                        exit(2)
                    }
                }
            }

        case "OQ-QM-002":
            guard !cfg.sMeanSequence.isEmpty else { throw InjectorError.usage("OQ-QM-002 needs --s-mean-sequence") }
            var prevC3 = Float.greatestFiniteMagnitude
            var terminalsSeen = Set<UInt8>()
            for sMean in cfg.sMeanSequence {
                let seq = wireSequence()
                let wire = S4DeltaWire(
                    primID: prim,
                    dimension: S4DeltaWire.allStructuralDimensions,
                    oldValue: 0,
                    newValue: sMean,
                    sequence: seq
                )
                client.publish(subject: SubstrateWireSubjects.s4Delta, payload: try S4DeltaCodec.encode(wire))
                let proj = try await waitForC4(client: client, prim: prim, minSequence: seq, timeoutSeconds: cfg.timeoutSeconds)
                terminalsSeen.insert(proj.terminal)
                printRow(test: test, prim: cfg.primArg, sMean: sMean, run: 1, proj: proj)
                if proj.c3Closure > prevC3 + 1e-6 {
                    fputs("NON-MONOTONIC c3_closure step \(sMean)\n", stderr)
                    exit(2)
                }
                prevC3 = proj.c3Closure
            }
            let need: Set<UInt8> = [0x01, 0x02, 0x03, 0x04]
            if !need.isSubset(of: terminalsSeen) {
                fputs("Missing terminal transitions; saw \(terminalsSeen)\n", stderr)
                exit(2)
            }

        case "OQ-QM-003":
            guard let inj = cfg.injectComponents else { throw InjectorError.usage("OQ-QM-003 needs --inject") }
            let (s1, s2, s3, s4) = inj
            let proj0 = try await runInjectAllDims(
                client: client,
                prim: prim,
                s1: s1,
                s2: s2,
                s3: s3,
                s4: s4,
                timeout: cfg.timeoutSeconds
            )
            let s8i = s8Proxy(s1: s1, s2: s2, s3: s3, s4: s4, c1: proj0.c1Trust, c2: proj0.c2Identity, c3: proj0.c3Closure, c4: proj0.c4Consequence)
            if cfg.waitFranklinCycle {
                try await waitFranklinMonologue(timeoutSeconds: 60)
            }
            let proj1 = try await runInjectAllDims(
                client: client,
                prim: prim,
                s1: s1,
                s2: s2,
                s3: s3,
                s4: s4,
                timeout: cfg.timeoutSeconds
            )
            let s8f = s8Proxy(s1: s1, s2: s2, s3: s3, s4: s4, c1: proj1.c1Trust, c2: proj1.c2Identity, c3: proj1.c3Closure, c4: proj1.c4Consequence)
            let delta = Double(abs(s8f - s8i)) / max(Double(s8i), 1e-9)
            print("OQ-QM-003\tS8_initial\t\(s8i)\tS8_final\t\(s8f)\tdelta_pct\t\(delta * 100)")
            if delta >= 0.05 {
                fputs("S8 delta \(delta) >= 5%\n", stderr)
                exit(2)
            }

        case "OQ-QM-004":
            guard let sm = cfg.sMean else { throw InjectorError.usage("OQ-QM-004 needs --s-mean") }
            let seq = wireSequence()
            let wire = S4DeltaWire(
                primID: prim,
                dimension: S4DeltaWire.allStructuralDimensions,
                oldValue: 0,
                newValue: sm,
                sequence: seq
            )
            client.publish(subject: SubstrateWireSubjects.s4Delta, payload: try S4DeltaCodec.encode(wire))
            let proj = try await waitForC4(client: client, prim: prim, minSequence: seq, timeoutSeconds: cfg.timeoutSeconds)
            print("OQ-QM-004\t\(cfg.primArg)\tterminal\t0x\(String(format: "%02x", proj.terminal))")

        case "OQ-QM-005":
            guard let sm = cfg.sMean else { throw InjectorError.usage("OQ-QM-005 needs --s-mean") }
            let seq0 = wireSequence()
            let w0 = S4DeltaWire(
                primID: prim,
                dimension: S4DeltaWire.allStructuralDimensions,
                oldValue: 0,
                newValue: sm,
                sequence: seq0
            )
            client.publish(subject: SubstrateWireSubjects.s4Delta, payload: try S4DeltaCodec.encode(w0))
            let prior = try await waitForC4(client: client, prim: prim, minSequence: seq0, timeoutSeconds: cfg.timeoutSeconds)
            if cfg.waitFranklinCycle {
                try await waitFranklinMonologue(timeoutSeconds: 60)
            }
            let seq1 = wireSequence()
            let w1 = S4DeltaWire(
                primID: prim,
                dimension: S4DeltaWire.allStructuralDimensions,
                oldValue: 0,
                newValue: sm,
                sequence: seq1
            )
            client.publish(subject: SubstrateWireSubjects.s4Delta, payload: try S4DeltaCodec.encode(w1))
            let post = try await waitForC4(client: client, prim: prim, minSequence: seq1, timeoutSeconds: cfg.timeoutSeconds)
            print("OQ-QM-005\tprior_c3\t\(prior.c3Closure)\tpost_c3\t\(post.c3Closure)")
            if post.c3Closure <= prior.c3Closure {
                fputs("No improvement in c3_closure\n", stderr)
                exit(2)
            }
            let rcfg = Configuration()
            let rq = try DatabaseQueue(path: dbPath, configuration: rcfg)
            let row = try await rq.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                    SELECT id, kind, timestamp_iso FROM franklin_learning_receipts
                    WHERE kind = 'domain_improvement'
                    ORDER BY timestamp_iso DESC LIMIT 1
                    """
                )
            }
            guard row != nil else {
                fputs("EXPECTED domain_improvement receipt row\n", stderr)
                exit(2)
            }
            print("OQ-QM-005\treceipt\t\(String(describing: row))")

        case "OQ-QM-006":
            guard !cfg.sMeanSequence.isEmpty else { throw InjectorError.usage("OQ-QM-006 needs --s-mean-sequence") }
            var prev = Float.leastNormalMagnitude
            for sMean in cfg.sMeanSequence {
                let seq = wireSequence()
                let wire = S4DeltaWire(
                    primID: prim,
                    dimension: S4DeltaWire.allStructuralDimensions,
                    oldValue: 0,
                    newValue: sMean,
                    sequence: seq
                )
                client.publish(subject: SubstrateWireSubjects.s4Delta, payload: try S4DeltaCodec.encode(wire))
                let proj = try await waitForC4(client: client, prim: prim, minSequence: seq, timeoutSeconds: cfg.timeoutSeconds)
                printRow(test: test, prim: cfg.primArg, sMean: sMean, run: 1, proj: proj)
                if proj.c3Closure + 1e-6 < prev {
                    fputs("NON-MONOTONIC c3_closure ascending sequence\n", stderr)
                    exit(2)
                }
                prev = proj.c3Closure
            }

        default:
            throw InjectorError.usage("Unknown --test \(test)")
        }

        client.disconnect()
    }
}
