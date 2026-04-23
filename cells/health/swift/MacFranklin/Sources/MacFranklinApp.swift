import AdminCellCore
import AppKit
import Foundation
import SceneKit
import SwiftUI

@main
struct MacFranklinApp: App {
    @StateObject private var model = MacFranklinModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 560)
        }
    }
}

@MainActor
final class MacFranklinModel: ObservableObject {
    enum RuntimeState: String, Codable {
        case bootstrap = "BOOTSTRAP"
        case ready = "READY"
        case runningGames = "RUNNING_GAMES"
        case refused = "REFUSED"
        case cure = "CURE"
        case alive = "ALIVE"
    }

    struct RuntimeStateSnapshot: Codable {
        let schema: String
        let tsUTC: String
        let state: String
        let lifeGameStatus: String
        let lifeGamePassed: Bool
        let running: Bool
        let lastExit: Int32?
        let repoPath: String
    }

    fileprivate static let userDefaultsKey = "macfranklin_repo_root_v1"
    fileprivate static let usdSnippetName = "FranklinLiveCell"

    @Published var repoPath: String = UserDefaults.standard.string(forKey: MacFranklinModel.userDefaultsKey) ?? ""
    @Published var lastLog: String = ""
    @Published var running = false
    @Published var lastExit: Int32?
    @Published var discoveryNote: String = ""
    @Published var didAutoBindRepo = false
    @Published var bundledUsdaPath: String = ""
    @Published var usdaSnippet: String = ""
    @Published var lifeGameRunning = false
    @Published var lifeGamePassed = false
    @Published var lifeGameStatus: String = "LIFE game not started."
    @Published var didAutoStartLifeGame = false
    @Published var runtimeState: RuntimeState = .bootstrap

    var repoURL: URL? {
        let p = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p).standardizedFileURL
    }

    var liveCellPathOK: Bool {
        validateRepo() == nil
    }

    func setRepoPath(_ path: String) {
        repoPath = path
        UserDefaults.standard.set(path, forKey: MacFranklinModel.userDefaultsKey)
    }

    /// No manual "Choose repo" required when env, CWD, or app bundle is under the tree.
    func loadBundledOpenUSD() {
        if let u = Bundle.module.url(
            forResource: MacFranklinModel.usdSnippetName,
            withExtension: "usda"
        ) {
            bundledUsdaPath = u.path
            if let raw = try? String(contentsOf: u, encoding: .utf8) {
                usdaSnippet = String(raw.prefix(500))
            }
        }
    }

    func ensureLiveRepo() {
        if !repoPath.isEmpty, isValidRepoRoot(repoPath) {
            return
        }
        let r = RepoRootResolver()
        let envs = [
            "GAIAFTCL_REPO_ROOT",
            "GAIAHEALTH_REPO_ROOT"
        ]
        for k in envs {
            if let p = ProcessInfo.processInfo.environment[k], !p.isEmpty, isValidRepoRoot(p) {
                setRepoPath(p)
                didAutoBindRepo = true
                discoveryNote = "Repository from \(k)"
                return
            }
        }
        let seeds: [URL?] = [
            URL(fileURLWithPath: Bundle.main.bundlePath),
            Bundle.main.executableURL.map { $0.deletingLastPathComponent() },
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ]
        for s in seeds {
            guard let st = s else { continue }
            if let root = r.discoverWalkingUp(from: st) {
                setRepoPath(root.path)
                didAutoBindRepo = true
                discoveryNote = "Repository auto-located (walk from bundle / working directory)"
                return
            }
        }
        discoveryNote = "No tree found — set GAIAFTCL_REPO_ROOT or use Override…"
    }

    private func isValidRepoRoot(_ p: String) -> Bool {
        let u = URL(fileURLWithPath: p)
        return FileManager.default.fileExists(
            atPath: u.appendingPathComponent("cells/health/scripts/health_full_local_iqoqpq_gamp.sh").path
        )
    }

    func pickRepo() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.message = "Override gaiaFTCL / FoT8D root (optional — use when auto-locate is wrong)"
        p.prompt = "Select"
        if p.runModal() == .OK, let url = p.url {
            setRepoPath(url.path)
            lastLog = "Repo override: \(url.path)\n"
            discoveryNote = "Repository set manually"
        }
    }

    func validateRepo() -> String? {
        guard let r = repoURL else { return "GAMP5 needs a tree with cells/health — set GAIAFTCL_REPO_ROOT or Override…" }
        let script = r.appendingPathComponent("cells/health/scripts/health_full_local_iqoqpq_gamp.sh")
        if FileManager.default.fileExists(atPath: script.path) { return nil }
        return "Not a gaiaFTCL root: missing \(script.path)"
    }

    func runGamp5Smoke() {
        guard let err = validateRepo() else {
            lastLog = ""
            runtimeState = .runningGames
            persistRuntimeStateSnapshot()
            runDriver(smoke: true)
            return
        }
        runtimeState = .refused
        lastLog = err
        persistRuntimeStateSnapshot()
    }

    func runGamp5Full() {
        guard let err = validateRepo() else {
            lastLog = ""
            runtimeState = .runningGames
            persistRuntimeStateSnapshot()
            runDriver(smoke: false)
            return
        }
        runtimeState = .refused
        lastLog = err
        persistRuntimeStateSnapshot()
    }

    /// Boot-time, fail-closed runtime chain for a live cell.
    /// The app is not considered "alive" unless this chain exits green.
    func runLifeGameChain() {
        guard !lifeGameRunning else { return }
        if let err = validateRepo() {
            lifeGamePassed = false
            lifeGameStatus = "REFUSED: \(err)"
            runtimeState = .refused
            lastLog = err
            persistRuntimeStateSnapshot()
            return
        }
        guard let r = repoURL else { return }
        lifeGameRunning = true
        lifeGamePassed = false
        lifeGameStatus = "LIFE game running…"
        runtimeState = .runningGames
        running = true
        lastExit = nil
        persistRuntimeStateSnapshot()
        lastLog = """
        [LIFE] Boot chain start (fail-closed)
        [LIFE] 1) Klein narrative lock
        [LIFE] 2) Health catalog/game validate (--skip-cargo-test)
        [LIFE] 3) Franklin canonical driver smoke

        """

        let rPath = r.path
        Task { @MainActor in
            let (ok, code, out, status) = await Task.detached {
                MacFranklinModel.runLifeGameChainSync(repoPath: rPath)
            }.value
            self.running = false
            self.lifeGameRunning = false
            self.lastExit = code
            self.lastLog += out
            self.lifeGamePassed = ok
            self.lifeGameStatus = status
            if ok {
                self.runtimeState = .alive
                self.lastLog += "\n[LIFE] ALIVE: chain green. Evidence in cells/health/evidence/\n"
            } else {
                self.runtimeState = .refused
                self.lastLog += "\n[LIFE] REFUSED: chain failed. Cell not alive.\n"
            }
            self.persistRuntimeStateSnapshot()
        }
    }

    private func runDriver(smoke: Bool) {
        guard let r = repoURL else { return }
        let driver = r.appendingPathComponent("cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh")
        guard FileManager.default.fileExists(atPath: driver.path) else {
            lastLog = "Missing driver: \(driver.path)"
            return
        }
        running = true
        lastExit = nil
        lastLog = "Running: \(driver.lastPathComponent) (smoke=\(smoke))…\n"

        let rPath = r.path
        let dPath = driver.path
        let prefix = self.lastLog
        Task { @MainActor in
            let (code, out) = await Task.detached {
                MacFranklinModel.runFranklinDriverSync(repoPath: rPath, driverPath: dPath, smoke: smoke)
            }.value
            self.running = false
            self.lastExit = code
            self.lastLog = prefix + out
            if code != 0 {
                self.runtimeState = .refused
                self.lastLog += "\n(exit \(code))\n"
            } else {
                self.runtimeState = .cure
                self.lastLog += "\nOK (exit 0) — see cells/health/evidence/franklin_mac_admin_gamp5_*.json\n"
            }
            self.persistRuntimeStateSnapshot()
        }
    }

    private nonisolated static func runFranklinDriverSync(repoPath: String, driverPath: String, smoke: Bool) -> (Int32, String) {
        let r = URL(fileURLWithPath: repoPath)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [driverPath]
        p.currentDirectoryURL = r
        var env = RunEnvironment.baseline(for: r, inheritPath: true)
        env["GAIAFTCL_REPO_ROOT"] = r.path
        env["FRANKLIN_GAMP5_SMOKE"] = smoke ? "1" : "0"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let s = String(data: data, encoding: .utf8) ?? ""
            return (p.terminationStatus, s)
        } catch {
            return (1, "Process error: \(error)\n")
        }
    }

    private nonisolated static func runLifeGameChainSync(repoPath: String) -> (Bool, Int32, String, String) {
        let root = URL(fileURLWithPath: repoPath)
        var fullLog = ""

        // 1) Klein lock test
        let lockScript = root.appendingPathComponent("cells/franklin/tests/test_mac_mesh_cell_narrative_lock.sh").path
        let (lockCode, lockOut) = runScriptSync(
            executable: "/bin/zsh",
            arguments: [lockScript],
            repoPath: repoPath,
            envExtra: [:]
        )
        fullLog += "\n[LIFE][1/3] Klein lock exit \(lockCode)\n\(lockOut)\n"
        if lockCode != 0 {
            return (false, lockCode, fullLog, "REFUSED: Klein lock failed (exit \(lockCode))")
        }

        // 2) Health catalog/game validator (script includes Qualification-Catalog checks)
        let healthValidate = root.appendingPathComponent("cells/health/scripts/health_cell_gamp5_validate.sh").path
        let (healthCode, healthOut) = runScriptSync(
            executable: "/bin/zsh",
            arguments: [healthValidate, "--skip-cargo-test"],
            repoPath: repoPath,
            envExtra: [:]
        )
        fullLog += "\n[LIFE][2/3] Health catalog validate exit \(healthCode)\n\(healthOut)\n"
        if healthCode != 0 {
            return (false, healthCode, fullLog, "REFUSED: health catalog/game validate failed (exit \(healthCode))")
        }

        // 3) Franklin canonical driver smoke
        let driver = root.appendingPathComponent("cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh").path
        let (driverCode, driverOut) = runScriptSync(
            executable: "/bin/sh",
            arguments: [driver],
            repoPath: repoPath,
            envExtra: ["FRANKLIN_GAMP5_SMOKE": "1"]
        )
        fullLog += "\n[LIFE][3/3] Franklin smoke exit \(driverCode)\n\(driverOut)\n"
        if driverCode != 0 {
            return (false, driverCode, fullLog, "REFUSED: Franklin smoke failed (exit \(driverCode))")
        }

        return (true, 0, fullLog, "ALIVE: LIFE game chain green")
    }

    private nonisolated static func runScriptSync(
        executable: String,
        arguments: [String],
        repoPath: String,
        envExtra: [String: String]
    ) -> (Int32, String) {
        let r = URL(fileURLWithPath: repoPath)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.currentDirectoryURL = r
        var env = RunEnvironment.baseline(for: r, inheritPath: true)
        env["GAIAFTCL_REPO_ROOT"] = r.path
        env["GAIAHEALTH_REPO_ROOT"] = r.path
        for (k, v) in envExtra {
            env[k] = v
        }
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let s = String(data: data, encoding: .utf8) ?? ""
            return (p.terminationStatus, s)
        } catch {
            return (1, "Process error: \(error)\n")
        }
    }

    func openEvidenceFolder() {
        guard let r = repoURL else { return }
        let ev = r.appendingPathComponent("cells/health/evidence", isDirectory: true)
        NSWorkspace.shared.open(ev)
    }

    /// Rust stdio MCP server binary path in-repo build output.
    var mcpRustServerBinaryPath: String? {
        guard let r = repoURL else { return nil }
        return r
            .appendingPathComponent("target/release/macfranklin_mcp_server", isDirectory: false)
            .path
    }

    var mcpRustServerExists: Bool {
        guard let p = mcpRustServerBinaryPath else { return false }
        return FileManager.default.isExecutableFile(atPath: p)
    }

    /// Paste into `~/.cursor/mcp.json` (see `mcp/MCP_CURSOR.md`)
    var cursorMcpConfigJSON: String {
        guard let r = repoURL, let bin = mcpRustServerBinaryPath else {
            return ""
        }
        let root = MacFranklinModel.jsonEscapeForJSON(r.path)
        let be = MacFranklinModel.jsonEscapeForJSON(bin)
        return """
        {
          "mcpServers": {
            "macfranklin": {
              "command": "\(be)",
              "args": [],
              "env": {
                "GAIAFTCL_REPO_ROOT": "\(root)"
              }
            }
          }
        }
        """
    }

    fileprivate static func jsonEscapeForJSON(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func copyCursorMcpConfigToPasteboard() {
        let j = cursorMcpConfigJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !j.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(j, forType: .string)
        lastLog += "\n[MacFranklin] Copied Cursor MCP config JSON to pasteboard. Merge into ~/.cursor/mcp.json — see mcp/MCP_CURSOR.md\n"
    }

    func openMcpCursorDoc() {
        guard let r = repoURL else { return }
        let u = r.appendingPathComponent("cells/health/swift/MacFranklin/mcp/MCP_CURSOR.md", isDirectory: false)
        NSWorkspace.shared.open(u)
    }

    func persistRuntimeStateSnapshot() {
        guard let r = repoURL else { return }
        let dir = r.appendingPathComponent("cells/health/evidence/macfranklin_state", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ts = iso8601UTCNowFilenameSafe()
            let out = dir.appendingPathComponent("state_\(ts).json", isDirectory: false)
            let snap = RuntimeStateSnapshot(
                schema: "macfranklin_runtime_state_v1",
                tsUTC: iso8601UTCNow(),
                state: runtimeState.rawValue,
                lifeGameStatus: lifeGameStatus,
                lifeGamePassed: lifeGamePassed,
                running: running,
                lastExit: lastExit,
                repoPath: r.path
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(snap)
            try data.write(to: out, options: .atomic)
        } catch {
            lastLog += "\n[MacFranklin] snapshot write error: \(error)\n"
        }
    }

    private func iso8601UTCNow() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    private func iso8601UTCNowFilenameSafe() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        return f.string(from: Date())
    }
}

// MARK: - OpenUSD live scene (Model I/O + SceneKit; orbit to play)
final class UsdGameCoordinator: NSObject {
    var spinNode: SCNNode?
}

struct UsdOpenCellGameView: NSViewRepresentable {
    @Binding var gampRunActive: Bool
    @Binding var liveRepoOK: Bool

    func makeCoordinator() -> UsdGameCoordinator { UsdGameCoordinator() }

    func makeNSView(context: Context) -> SCNView {
        let scn = SCNView()
        scn.allowsCameraControl = true
        scn.showsStatistics = false
        scn.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0)
        scn.autoenablesDefaultLighting = true
        // OpenUSD: `FranklinLiveCell.usda` is bundled (single cell + orbit puck) — same layout as the Scene below.
        let scene = makeLiveCellGameScene()
        scn.scene = scene

        var spinTarget: SCNNode? = scene.rootNode.childNode(withName: "LiveCell", recursively: true)
        if spinTarget == nil { spinTarget = scene.rootNode }
        context.coordinator.spinNode = spinTarget

        if scn.scene?.rootNode.childNode(withName: "macfranklinCamera", recursively: true) == nil {
            let cameraNode = SCNNode()
            cameraNode.name = "macfranklinCamera"
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 0.2, 2.4)
            scene.rootNode.addChildNode(cameraNode)
        }

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .omni
        sun.position = SCNVector3(2, 4, 3)
        scene.rootNode.addChildNode(sun)

        let spin = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi / 90, z: 0, duration: 0.1)
        )
        spinTarget?.runAction(spin, forKey: "spin")
        return scn
    }

    func updateNSView(_ scn: SCNView, context: Context) {
        _ = gampRunActive
        _ = liveRepoOK
    }

    /// Matches `FranklinLiveCell.usda`: `LiveCell` xform, Plasma sphere, Puck in orbit.
    private func makeLiveCellGameScene() -> SCNScene {
        let s = SCNScene()
        let live = SCNNode()
        live.name = "LiveCell"

        let plasma = SCNNode(geometry: SCNSphere(radius: 0.5))
        plasma.name = "Plasma"
        plasma.geometry?.firstMaterial?.diffuse.contents = NSColor(
            calibratedRed: 0.1,
            green: 0.55,
            blue: 0.95,
            alpha: 1.0
        )
        live.addChildNode(plasma)

        let puck = SCNNode(geometry: SCNSphere(radius: 0.12))
        puck.name = "Puck"
        puck.position = SCNVector3(0.75, 0, 0)
        puck.geometry?.firstMaterial?.diffuse.contents = NSColor.systemOrange
        live.addChildNode(puck)

        s.rootNode.addChildNode(live)
        return s
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: MacFranklinModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenUSD live cell")
                        .font(.title2.weight(.semibold))
                    Text("Orbit, drag, zoom the scene. Spin reflects GAMP5 + repo. Franklin admin cell; same driver as Terminal.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if model.liveCellPathOK {
                    Label("GAMP5 path OK", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("GAMP5 path needs tree", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                UsdOpenCellGameView(
                    gampRunActive: $model.running,
                    liveRepoOK: Binding(
                        get: { model.liveCellPathOK },
                        set: { _ in }
                    )
                )
                .frame(minHeight: 300, maxHeight: .infinity)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 8) {
                    if !model.bundledUsdaPath.isEmpty {
                        Text("Bundled OpenUSD: \(URL(fileURLWithPath: model.bundledUsdaPath).lastPathComponent)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if !model.usdaSnippet.isEmpty {
                            Text(model.usdaSnippet + (model.usdaSnippet.count >= 500 ? "…" : ""))
                                .font(.system(size: 9, design: .monospaced))
                                .frame(maxHeight: 72, alignment: .topLeading)
                                .padding(4)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(4)
                        }
                    }
                    Text(model.discoveryNote.isEmpty ? "…" : model.discoveryNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text((model.repoPath.isEmpty) ? "Repository: (searching or unset)" : "Repository: " + model.repoPath)
                        .lineLimit(3)
                        .font(.caption)
                        .truncationMode(.middle)
                    HStack {
                        Spacer()
                        Button("Override repository…") { model.pickRepo() }
                    }
                    HStack(spacing: 8) {
                        Button("Run LIFE game chain") { model.runLifeGameChain() }
                            .disabled(model.running || model.lifeGameRunning)
                        Button("Run GAMP5 smoke") { model.runGamp5Smoke() }
                            .disabled(model.running || model.lifeGameRunning)
                        Button("Run full GAMP5") { model.runGamp5Full() }
                            .disabled(model.running || model.lifeGameRunning)
                    }
                    Button("Open evidence folder") { model.openEvidenceFolder() }
                    Text(model.lifeGameStatus)
                        .font(.caption2)
                        .foregroundStyle(model.lifeGamePassed ? .green : .secondary)
                    Text("Runtime state: \(model.runtimeState.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(model.runtimeState == .alive ? .green : .secondary)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Co-work with Cursor (MCP)")
                                .font(.subheadline.weight(.semibold))
                            if model.mcpRustServerExists {
                                Text("Rust stdio MCP server present — use Copy, then merge into Cursor MCP config.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("Build Rust MCP server: cargo build -p macfranklin_mcp_server --release (see MCP_CURSOR.md).")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack {
                                Button("Copy Cursor MCP config JSON") { model.copyCursorMcpConfigToPasteboard() }
                                    .disabled(!model.mcpRustServerExists)
                                Button("Open MCP_CURSOR.md") { model.openMcpCursorDoc() }
                            }
                        }
                    } label: {
                        Text("MCP (Cursor agent)")
                    }

                    if let e = model.lastExit {
                        Text("Last exit: \(e)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 300, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            ScrollView {
                Text(model.lastLog.isEmpty ? "GAMP5 output will appear here." : model.lastLog)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 120)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(16)
        .onAppear {
            model.loadBundledOpenUSD()
            model.ensureLiveRepo()
            model.runtimeState = model.liveCellPathOK ? .ready : .bootstrap
            model.persistRuntimeStateSnapshot()
            if !model.didAutoStartLifeGame {
                model.didAutoStartLifeGame = true
                model.runLifeGameChain()
            }
        }
    }
}
