// ConstitutionalTests.swift — SwiftTestRobit
//
// Contract tests for the WASM constitutional substrate's 8 exports.
// These tests call the JS layer via a headless WKWebView loaded with
// the compiled gaia_health_substrate.wasm. They verify that the WASM
// binary exports all 8 required functions and that each returns the
// correct result for known test vectors.
//
// Note: WKWebView requires a runloop. The TestRobit harness provides one.
// If wasm_constitutional/pkg/ does not exist yet (pre-build), these
// tests report SKIP rather than FAIL — they become active after wasm-pack build.

import Foundation
import WebKit

// WASM package expected at this path (relative to TestRobit working dir)
private let wasmPkgPath = "../../wasm_constitutional/pkg"

enum ConstitutionalTests {
    static func runAll() async {
        guard FileManager.default.fileExists(atPath: wasmPkgPath + "/gaia_health_substrate.js") else {
            print("  \u{001B}[1;33m⚠ SKIP\u{001B}[0m  [TR-S5-*] WASM pkg not built — run: cd wasm_constitutional && wasm-pack build --target web --release")
            return
        }

        await run("TR-S5-001", "WASM exports binding_constitutional_check") {
            try await wasmExports("binding_constitutional_check")
        }

        await run("TR-S5-002", "WASM exports admet_bounds_check") {
            try await wasmExports("admet_bounds_check")
        }

        await run("TR-S5-003", "WASM exports phi_boundary_check") {
            try await wasmExports("phi_boundary_check")
        }

        await run("TR-S5-004", "WASM exports epistemic_chain_validate") {
            try await wasmExports("epistemic_chain_validate")
        }

        await run("TR-S5-005", "WASM exports consent_validity_check") {
            try await wasmExports("consent_validity_check")
        }

        await run("TR-S5-006", "WASM exports force_field_bounds_check") {
            try await wasmExports("force_field_bounds_check")
        }

        await run("TR-S5-007", "WASM exports selectivity_check") {
            try await wasmExports("selectivity_check")
        }

        await run("TR-S5-008", "WASM exports get_epistemic_tag") {
            try await wasmExports("get_epistemic_tag")
        }

        // Functional contract tests
        await run("TR-S5-009", "WASM: valid binding params → AlarmResult.Pass (0)") {
            try await wasmCall(
                fn: "binding_constitutional_check",
                args: [#"{"binding_dg":-8.5,"buried_surface_ang2":650.0,"steric_clash":false}"#],
                expected: "0"
            )
        }

        await run("TR-S5-010", "WASM: hERG IC50 0.5 µM → ADMETResult.HergCardiacRisk (1)") {
            try await wasmCall(
                fn: "admet_bounds_check",
                args: [#"{"mol_weight_da":350.0,"clogp":2.5,"herg_ic50_um":0.5,"ld50_mg_kg":300.0,"oral_f_pct":60.0}"#],
                expected: "1"
            )
        }

        await run("TR-S5-011", "ZERO-PII: phi_boundary_check accepts 64-char hex hash") {
            try await wasmCall(
                fn: "phi_boundary_check",
                args: [String(repeating: "a", count: 64)],
                expected: "0" // PHIResult.Clean
            )
        }

        await run("TR-S5-012", "ZERO-PII: phi_boundary_check rejects raw text (PHI alert)") {
            try await wasmCall(
                fn: "phi_boundary_check",
                args: ["Patient John Doe DOB 01/15/1980"],
                expected: "1" // PHIResult.PhiAlert
            )
        }

        await run("TR-S5-013", "WASM: assumed-only chain → ChainResult.AssumedBindingOnly (1)") {
            try await wasmCall(
                fn: "epistemic_chain_validate",
                args: [#"{"input_tag":2,"computation_tag":2,"output_tag":2}"#],
                expected: "1"
            )
        }

        await run("TR-S5-014", "ZERO-PII: consent_validity_check rejects patient name as pubkey") {
            try await wasmCall(
                fn: "consent_validity_check",
                args: ["Richard Gillespie", "0", "1000"],
                expected: "3" // ConsentResult.InvalidKey
            )
        }

        await run("TR-S5-015", "WASM: hERG score 0.85 → SelectivityResult.Unsafe (3)") {
            try await wasmCall(
                fn: "selectivity_check",
                args: [#"{"herg_score":0.85,"off_target_count":2,"critical_off_target":false}"#],
                expected: "3"
            )
        }

        await run("TR-S5-016", "WASM: get_epistemic_tag returns Measured (0) for measured source") {
            try await wasmCall(
                fn: "get_epistemic_tag",
                args: [#"{"source_type":"measured"}"#],
                expected: "0"
            )
        }
    }

    // ── WASM helpers ──────────────────────────────────────────────────────────

    static func wasmExports(_ funcName: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let wv = WKWebView(frame: .zero)
                let jsPath = "\(wasmPkgPath)/gaia_health_substrate.js"
                guard let jsText = try? String(contentsOfFile: jsPath) else {
                    continuation.resume(returning: false)
                    return
                }
                let html = """
                <script>\(jsText)</script>
                <script>
                  document.title = typeof wasm_bindgen.\(funcName) === 'function' ? 'true' : 'false';
                </script>
                """
                wv.loadHTMLString(html, baseURL: URL(fileURLWithPath: wasmPkgPath))
                // Simple polling — replace with proper WKNavigationDelegate in production
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    wv.evaluateJavaScript("typeof wasm_bindgen.\(funcName) === 'function'") { result, _ in
                        continuation.resume(returning: (result as? Bool) ?? false)
                    }
                }
            }
        }
    }

    static func wasmCall(fn: String, args: [String], expected: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let wv = WKWebView(frame: .zero)
                let jsPath = "\(wasmPkgPath)/gaia_health_substrate.js"
                guard let jsText = try? String(contentsOfFile: jsPath) else {
                    continuation.resume(returning: false)
                    return
                }
                let argsJs = args.map { "'\($0)'" }.joined(separator: ", ")
                let eval = "String(wasm_bindgen.\(fn)(\(argsJs)))"
                let html = "<script>\(jsText)</script>"
                wv.loadHTMLString(html, baseURL: URL(fileURLWithPath: wasmPkgPath))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    wv.evaluateJavaScript(eval) { result, _ in
                        let got = (result as? String) ?? ""
                        continuation.resume(returning: got == expected)
                    }
                }
            }
        }
    }
}
