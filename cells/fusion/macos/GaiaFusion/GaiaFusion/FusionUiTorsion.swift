import Foundation

/// C4 “torsion” for the embedded S4 surface: mismatch among Klein bottle (bundle), WASM/DOM witness, TSX invariant token, and native monolithic `usd_px`.
/// 0 = closed; 1 = maximum drift (all four false).
enum FusionUiTorsion {
    static func score01(health: [String: Any]) -> Double {
        let kb = health["klein_bottle_closed"] as? Bool ?? false
        let wasm = health["wasm_surface"] as? [String: Any] ?? [:]
        let dom = wasm["closed"] as? Bool ?? false
        let tsx = wasm["fusion_tsx_surface"] as? [String: Any]
        let tsxOk = tsx?["closed"] as? Bool ?? false
        let usd = health["usd_px"] as? [String: Any] ?? [:]
        let pxrVi = usd["pxr_version_int"] as? Int ?? 0
        let memOk = usd["in_memory_stage"] as? Bool ?? false
        let pcvOk = usd["plant_control_viewport_prim"] as? Bool ?? false
        let usdOk = pxrVi > 0 && memOk && pcvOk
        let satisfied = [kb, dom, tsxOk, usdOk].filter { $0 }.count
        return 1.0 - Double(satisfied) / 4.0
    }

    /// Repo root containing `services/gaiaos_ui_web` (for `npx playwright`). `GAIA_ROOT` env wins.
    static func resolveGaiaRepoRoot() -> URL? {
        if let env = ProcessInfo.processInfo.environment["GAIA_ROOT"], !env.isEmpty {
            let u = URL(fileURLWithPath: env, isDirectory: true)
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("services/gaiaos_ui_web/package.json").path) {
                return u
            }
        }
        if let custom = UserDefaults.standard.string(forKey: "fusion_gaia_repo_root"), !custom.isEmpty {
            let u = URL(fileURLWithPath: custom, isDirectory: true)
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("services/gaiaos_ui_web/package.json").path) {
                return u
            }
        }
        var url = Bundle.main.bundleURL
        for _ in 0 ..< 14 {
            let candidate = url.appendingPathComponent("services/gaiaos_ui_web/package.json", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            url = url.deletingLastPathComponent()
            if url.path == "/" {
                break
            }
        }
        return nil
    }
}

/// Runs the same Playwright spec as `scripts/run_fusion_mac_app_gate.py` against this process’s `LocalServer`.
enum FusionPlaywrightHealRunner {
    static func runGate(repoRoot: URL, localPort: Int) -> (ok: Bool, summary: String) {
        let ui = repoRoot.appendingPathComponent("services/gaiaos_ui_web", isDirectory: true)
        let specRel = "tests/fusion/fusion_mac_wasm_gate.spec.ts"
        let specPath = ui.appendingPathComponent(specRel)
        guard FileManager.default.fileExists(atPath: specPath.path) else {
            return (false, "REFUSED: missing \(specPath.path)")
        }
        let base = "http://127.0.0.1:\(localPort)"
        let script = """
        export GAIA_ROOT='\(repoRoot.path.replacingOccurrences(of: "'", with: "'\\''") )'
        export FUSION_MAC_GATE_BASE_URL='\(base)'
        cd '\(ui.path.replacingOccurrences(of: "'", with: "'\\''") )' && exec npx playwright test '\(specRel)' --config=playwright.fusion.config.ts
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", script]
        proc.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return (false, "REFUSED: \(error.localizedDescription)")
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let tail = String(data: data, encoding: .utf8) ?? ""
        let ok = proc.terminationStatus == 0
        let short = tail.split(separator: "\n").suffix(24).joined(separator: "\n")
        return (ok, ok ? "CALORIE: playwright exit 0\n\(short)" : "REFUSED: rc=\(proc.terminationStatus)\n\(short)")
    }
}
