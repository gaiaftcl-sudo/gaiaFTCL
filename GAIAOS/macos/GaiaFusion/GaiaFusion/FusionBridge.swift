import Foundation
import WebKit
import CryptoKit

private enum ReceiptVector: String, CaseIterable {
    case zero = "00"
    case one = "01"
    case two = "10"
    case three = "11"
}

@MainActor
final class FusionBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    struct BridgeRequest: Sendable {
        let action: String
        let requestID: String
        let cellID: String?
        let inputPlantType: String?
        let outputPlantType: String?
        let raw: [String: String]
    }

    /// DOM + open shadow-root traversal witness from the fusion-s4 WKWebView (MutationObserver + heartbeat).
    struct WasmDomSurfaceWitness: Sendable {
        let shadowRootsEnumerated: Int
        let documentNodesApprox: Int
        let treeDepthMax: Int
        let href: String
        let tsMs: Int64
        let reason: String
    }

    private weak var meshManagerRef: MeshStateManager?
    private weak var webViewRef: WKWebView?
    var identityHashProvider: (() -> String?)?
    var traceModeProvider: (() -> Bool)?
    /// Fired once when WKWebView attaches — used for Boot-to-Tokamak native→JS session publish after `webViewRef` is non-nil.
    var onWebViewAttached: (() -> Void)?
    /// Native OpenUSD playback: operator pressed ENGAGE in S4.
    var onEngageIgnitionPlayback: (() -> Void)?
    /// Archetype / input plant select → load `plants/<kind>/root.usda`.
    var onViewportPlantKind: ((String) -> Void)?
    /// `SELECT_CELL` from WKWebView — syncs `AppCoordinator.selectedCellID` for SubGame Z.
    var applyRemoteCellSelection: ((String?) -> Void)?
    @Published var lastAction = "init"
    @Published private(set) var lastWasmDomWitness: WasmDomSurfaceWitness?
    /// Latest `tsx_invariant` object from the injected DOM witness (fusion-s4 publishes `window.__GAIAFTCL_FUSION_SURFACE`).
    @Published private(set) var lastTsxSurfaceEnvelope: [String: Any]?
    /// True after WKUserScript + `domWitness` handler are installed on the web view configuration.
    private(set) var wasmDomMonitoringInstalled: Bool = false

    /// Last successful `WebAssembly.instantiate` / `instantiateStreaming` witness (separate from DOM `wasm_surface`).
    struct WasmRuntimeWitness: Sendable {
        let ok: Bool
        let path: String
        let tsMs: Int64
        let fallbackFromStreaming: Bool
        let reason: String
    }

    @Published private(set) var lastWasmRuntimeWitness: WasmRuntimeWitness?

    private static let expectedTsxSchema = "gaiaftcl_fusion_s4_tsx_surface_v1"
    private static let wasmRuntimeSchema = "gaiaftcl_wasm_runtime_v1"

    private let processQueue = DispatchQueue(label: "fusion.bridge.process", qos: .utility)
    private let isoFormatter = ISO8601DateFormatter()
    private let transitionOrder: [ReceiptVector] = [.zero, .one, .two, .three]

    /// MSV Stage 2: signed transition vectors for viewport plant changes stay **pending** until
    /// `notifyUsdEversionComplete` fires (C4 moored to S4 — no vectors before USD stage + eversion terminal).
    private struct PendingEversionBatch {
        let action: String
        let requestID: String
        let context: [String: Any]
        let description: String
        let expectedPlantKind: String
    }

    private var eversionPendingBatches: [PendingEversionBatch] = []

    weak var layoutManager: CompositeLayoutManager?
    weak var fusionCellStateMachine: FusionCellStateMachine?
    
    init(meshManager: MeshStateManager) {
        self.meshManagerRef = meshManager
    }

    /// Plant HEAL/SWAP/RUN_MATRIX in S4 must not depend on SwiftUI "trace layer" chrome — only on a live WKWebView shell.
    private var operatorControlsArmed: Bool {
        webViewRef != nil
    }

    func attachWebView(_ webView: WKWebView) {
        webViewRef = webView
        wasmDomMonitoringInstalled = true
        sendDirect(
            action: "hello",
            data: [
                "ok": true,
                "message": "fusion bridge attached",
            ],
        )
        onWebViewAttached?()
    }

    /// JSON-shaped fragment for `/api/fusion/health` — `closed` means a fresh DOM/shadow snapshot arrived recently.
    func wasmSurfacePayloadForHealth(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1_000.0)) -> [String: Any] {
        let maxAgeMs: Int64 = 8_000
        guard let w = lastWasmDomWitness else {
            return [
                "schema": "gaiaftcl_wasm_dom_surface_v1",
                "monitoring": wasmDomMonitoringInstalled,
                "closed": false,
                "note": "awaiting first DOM/shadow snapshot from WebView",
            ]
        }
        let age = nowMs - w.tsMs
        let fresh = age >= 0 && age <= maxAgeMs && w.documentNodesApprox > 0
        var out: [String: Any] = [
            "schema": "gaiaftcl_wasm_dom_surface_v1",
            "monitoring": wasmDomMonitoringInstalled,
            "closed": fresh,
            "shadow_roots_enumerated": w.shadowRootsEnumerated,
            "document_nodes_approx": w.documentNodesApprox,
            "tree_depth_max": w.treeDepthMax,
            "href": w.href,
            "last_reason": w.reason,
            "last_ts_ms": w.tsMs,
            "age_ms": age,
        ]
        if let env = lastTsxSurfaceEnvelope {
            let schema = env["schema"] as? String ?? ""
            let inv = env["invariant_id"] as? String ?? ""
            let tsxClosed = schema == Self.expectedTsxSchema && !inv.isEmpty
            out["fusion_tsx_surface"] = [
                "schema": schema,
                "closed": tsxClosed,
                "envelope": env,
            ] as [String: Any]
        } else {
            out["fusion_tsx_surface"] = [
                "closed": false,
                "note": "tsx invariant not observed in DOM witness payload",
            ] as [String: Any]
        }
        return out
    }

    /// JSON fragment for `/api/fusion/health` — `wasm_runtime` (never merged with `wasm_surface`).
    func wasmRuntimePayloadForHealth(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1_000.0)) -> [String: Any] {
        guard let w = lastWasmRuntimeWitness else {
            return [
                "schema": Self.wasmRuntimeSchema,
                "closed": false,
                "note": "awaiting WebAssembly instantiate witness from WKWebView",
            ]
        }
        let age = nowMs - w.tsMs
        // Runtime closure is sticky once instantiate succeeds; health should not flap to false on age alone.
        let fresh = w.ok
        return [
            "schema": Self.wasmRuntimeSchema,
            "closed": fresh,
            "ok": w.ok,
            "instantiate_path": w.path,
            "last_ts_ms": w.tsMs,
            "age_ms": age,
            "fallback_from_streaming": w.fallbackFromStreaming,
            "last_reason": w.reason,
        ]
    }

    private static let internalDomProbeSchema = "gaiaftcl_fusion_internal_dom_probe_v1"

    /// In-app DOM / surface snapshot for `/api/fusion/self-probe` — WKWebView `evaluateJavaScript` parity with external Playwright for layout and fusion-s4 markers (no Node in the .app bundle).
    @MainActor
    func runInternalDomProbe(completion: @escaping ([String: Any]) -> Void) {
        guard let webView = webViewRef else {
            completion([
                "schema": Self.internalDomProbeSchema,
                "webview_attached": false,
                "note": "WKWebView not attached to FusionBridge yet",
            ])
            return
        }
        let js = """
        (function(){
          try {
            var surf = window.__GAIAFTCL_FUSION_SURFACE;
            function bg(sel) {
              try {
                var el = document.querySelector(sel);
                if (!el) { return ''; }
                return String(window.getComputedStyle(el).backgroundColor || '');
              } catch (e) { return ''; }
            }
            var root = document.documentElement;
            var htmlBg = root ? String(window.getComputedStyle(root).backgroundColor || '') : '';
            var bodyBg = (document.body) ? String(window.getComputedStyle(document.body).backgroundColor || '') : '';
            return JSON.stringify({
              schema: "\(Self.internalDomProbeSchema)",
              webview_attached: true,
              href: String(location.href || ''),
              pathname: String(location.pathname || ''),
              title: String(document.title || ''),
              body_text_len: (document.body && document.body.innerText) ? document.body.innerText.length : 0,
              document_element_count: document.getElementsByTagName('*').length,
              fusion_tsx_envelope_present: (typeof surf !== 'undefined' && surf !== null),
              user_agent: String(navigator.userAgent || ''),
              computed_bg_html: htmlBg,
              computed_bg_body: bodyBg,
              computed_bg_fusion_main: bg('#fusion-s4-main'),
              computed_bg_topology: bg('#fusion-topology-view'),
              html_class_gaiafusion_native: (root && root.classList && root.classList.contains('gaiafusion-native-bg')) ? true : false
            });
          } catch (e) {
            return JSON.stringify({ schema: "\(Self.internalDomProbeSchema)", webview_attached: true, error: String(e) });
          }
        })();
        """
        // Invoke completion synchronously on WebKit's callback thread so LocalServer's semaphore is never
        // gated behind a second MainActor hop (avoids deadlock / empty HTTP replies under load).
        webView.evaluateJavaScript(js) { result, error in
            if let evalError = error {
                completion([
                    "schema": Self.internalDomProbeSchema,
                    "webview_attached": true,
                    "evaluate_error": evalError.localizedDescription,
                ])
                return
            }
            if let s = result as? String,
               let data = s.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                completion(obj)
                return
            }
            completion([
                "schema": Self.internalDomProbeSchema,
                "webview_attached": true,
                "raw_evaluate_type": String(describing: type(of: result)),
            ])
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "domWitness" {
            ingestDomWitnessMessage(message.body)
            return
        }
        if message.name == "wasmRuntime" {
            ingestWasmRuntimeMessage(message.body)
            return
        }
        guard message.name == "fusionBridge" else {
            return
        }
        handle(message.body)
    }

    private func ingestWasmRuntimeMessage(_ body: Any) {
        guard let envelope = body as? [String: Any] else {
            return
        }
        let tsMs: Int64
        if let n = envelope["ts_ms"] as? Int64 {
            tsMs = n
        } else if let n = envelope["ts_ms"] as? Int {
            tsMs = Int64(n)
        } else if let n = envelope["ts_ms"] as? Double {
            tsMs = Int64(n)
        } else {
            tsMs = Int64(Date().timeIntervalSince1970 * 1_000.0)
        }
        let ok = (envelope["ok"] as? Bool) ?? false
        let path = (envelope["path"] as? String) ?? "unknown"
        let fallback = (envelope["fallback_from_streaming"] as? Bool) ?? false
        let reason = (envelope["reason"] as? String) ?? ""
        lastWasmRuntimeWitness = WasmRuntimeWitness(
            ok: ok,
            path: path,
            tsMs: tsMs,
            fallbackFromStreaming: fallback,
            reason: reason,
        )
    }

    private func ingestDomWitnessMessage(_ body: Any) {
        guard let envelope = body as? [String: Any] else {
            return
        }
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        let tsMs: Int64
        if let n = envelope["ts"] as? Int64 {
            tsMs = n
        } else if let n = envelope["ts"] as? Int {
            tsMs = Int64(n)
        } else if let n = envelope["ts"] as? Double {
            tsMs = Int64(n)
        } else {
            tsMs = Int64(Date().timeIntervalSince1970 * 1_000.0)
        }
        let reason = (envelope["reason"] as? String) ?? "unknown"
        let shadowRoots: Int
        if let n = payload["shadow_roots"] as? Int {
            shadowRoots = n
        } else if let n = payload["shadow_roots"] as? NSNumber {
            shadowRoots = n.intValue
        } else {
            shadowRoots = 0
        }
        let docNodes: Int
        if let n = payload["document_nodes_approx"] as? Int {
            docNodes = n
        } else if let n = payload["document_nodes_approx"] as? NSNumber {
            docNodes = n.intValue
        } else {
            docNodes = 0
        }
        let depth: Int
        if let n = payload["tree_depth_max"] as? Int {
            depth = n
        } else if let n = payload["tree_depth_max"] as? NSNumber {
            depth = n.intValue
        } else {
            depth = 0
        }
        let href = (payload["href"] as? String) ?? ""
        if let tsx = payload["tsx_invariant"] as? [String: Any] {
            lastTsxSurfaceEnvelope = tsx
        } else {
            lastTsxSurfaceEnvelope = nil
        }
        lastWasmDomWitness = WasmDomSurfaceWitness(
            shadowRootsEnumerated: shadowRoots,
            documentNodesApprox: docNodes,
            treeDepthMax: depth,
            href: href,
            tsMs: tsMs,
            reason: reason,
        )
    }

    func sendDirect(
        action: String,
        data: [String: Any] = [:],
        requestID: String = UUID().uuidString
    ) {
        Task { @MainActor in
            sendDictionary(
                payload: [
                    "action": action,
                    "type": action,
                    "request_id": requestID,
                    "ts_utc": isoFormatter.string(from: Date()),
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                    "data": data,
                ]
            )
        }
    }

    /// Hot-swap with explicit DOM annihilation before reload to prevent
    /// WebKit context bleed-through between successive fusion-s4 generations.
    func sterileHotSwapReload() {
        guard let webView = webViewRef else { return }
        let wipe = """
        try {
          if (document && document.documentElement) {
            document.documentElement.innerHTML = '';
          } else if (document && document.body) {
            document.body.innerHTML = '';
          }
        } catch (e) {}
        true;
        """
        webView.evaluateJavaScript(wipe) { _, _ in
            let cacheTypes: Set<String> = [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache]
            let fromEpoch = Date(timeIntervalSince1970: 0)
            WKWebsiteDataStore.default().removeData(ofTypes: cacheTypes, modifiedSince: fromEpoch) {
                webView.stopLoading()
                webView.reload()
            }
        }
    }

    private func sendReceipt(
        action: String,
        requestID: String,
        vector: ReceiptVector,
        description: String,
        context: [String: Any],
        signature: String,
        timestampMs: Int
    ) {
        Task { @MainActor in
            sendDictionary(
                payload: [
                    "action": "RECEIPT_UPDATE",
                    "type": "RECEIPT_UPDATE",
                    "request_id": requestID,
                    "id": "\(requestID)-\(vector.rawValue)-\(timestampMs)",
                    "vector": vector.rawValue,
                    "signature": signature,
                    "description": description,
                    "timestamp": timestampMs,
                    "ts_utc": isoFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1_000.0)),
                    "data": context,
                ]
            )
        }
    }

    /// Release the four signed receipt vectors (00→11) to the WKWebView immediately.
    private func releaseSignedTransitionReceiptVectors(for action: String, requestID: String, context: [String: Any], description: String) {
        for (index, vector) in transitionOrder.enumerated() {
            let timestampMs = Int(Date().timeIntervalSince1970 * 1_000.0) + index
            let details: [String: Any] = [
                "intent": action,
                "step": vector.rawValue,
                "sequence_step": index,
                "context": context,
                "context_count": context.keys.count,
            ]
            let signature = signTransition(
                action: action,
                vector: vector,
                requestID: requestID,
                timestampMs: timestampMs,
                details: details,
            )
            sendReceipt(
                action: action,
                requestID: requestID,
                vector: vector,
                description: description,
                context: details,
                signature: signature,
                timestampMs: timestampMs,
            )
        }
    }

    /// Queue or emit signed transition receipts. When `eversionGated` is true (viewport plant), vectors are held until
    /// **`notifyUsdEversionComplete`** — i.e. `USD_EVERSION_COMPLETE` / terminal swap lifecycle with loaded stage.
    private func emitSignedTransitionReceipts(
        for action: String,
        requestID: String,
        context: [String: Any] = [:],
        description: String,
        eversionGated: Bool = false,
        expectedPlantKindForGate: String? = nil
    ) {
        if eversionGated {
            let raw = expectedPlantKindForGate ?? (context["plant_kind"] as? String) ?? ""
            let pk = PlantType.normalized(raw: raw).rawValue
            var gatedCtx = context
            gatedCtx["eversion_gated"] = true
            gatedCtx["pending_release"] = true
            gatedCtx["expected_plant_kind"] = pk
            eversionPendingBatches.append(
                PendingEversionBatch(
                    action: action,
                    requestID: requestID,
                    context: gatedCtx,
                    description: description,
                    expectedPlantKind: pk
                )
            )
            return
        }
        releaseSignedTransitionReceiptVectors(for: action, requestID: requestID, context: context, description: description)
    }

    /// Called when `OpenUSDPlaybackController` reports terminal plant swap (`VERIFIED`) with a loaded USD stage.
    /// Flushes **FIFO** pending batches matching `plantKind` (normalized).
    func notifyUsdEversionComplete(plantKind raw: String, stageLoaded: Bool) {
        let pk = PlantType.normalized(raw: raw).rawValue
        guard stageLoaded else {
            return
        }
        var i = 0
        while i < eversionPendingBatches.count {
            let b = eversionPendingBatches[i]
            if b.expectedPlantKind == pk {
                let released = eversionPendingBatches.remove(at: i)
                var outCtx = released.context
                outCtx["eversion_gated"] = false
                outCtx["pending_release"] = false
                outCtx["usd_eversion_complete"] = true
                outCtx["eversion_signal"] = "USD_EVERSION_COMPLETE"
                releaseSignedTransitionReceiptVectors(
                    for: released.action,
                    requestID: released.requestID,
                    context: outCtx,
                    description: released.description,
                )
            } else {
                i += 1
            }
        }
    }

    private func signTransition(action: String, vector: ReceiptVector, requestID: String, timestampMs: Int, details: [String: Any]) -> String {
        let identityHash = identityHashProvider?() ?? "unverified"
        let signedInput: [String: Any] = [
            "action": action,
            "vector": vector.rawValue,
            "request_id": requestID,
            "timestamp": timestampMs,
            "identity_hash": identityHash,
            "details": details,
        ]
        let canonical = canonicalJSONString(signedInput)
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func canonicalJSONString(_ payload: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func normalizedAction(from raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func sendDictionary(payload: [String: Any]) {
        guard let webView = webViewRef else {
            return
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        let escaped = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = "if (window.fusionReceive) { window.fusionReceive('\(escaped)'); }"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func emitUITelemetrySync(snapshot: TelemetrySnapshot) {
        guard let webView = webViewRef else {
            return
        }
        let escIp = snapshot.tagIp.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escBt = snapshot.tagBt.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escNe = snapshot.tagNe.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let js = """
        (function(){
          window.dispatchEvent(new CustomEvent('fusion_telemetry', {
            detail: {
              action: 'UI_TELEMETRY_SYNC',
              payload: {
                I_p: \(snapshot.ip),
                B_T: \(snapshot.bt),
                n_e: \(snapshot.ne),
                class: \(snapshot.epistemicClass),
                tag_I_p: "\(escIp)",
                tag_B_T: "\(escBt)",
                tag_n_e: "\(escNe)"
              }
            }
          }));
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func handle(_ body: Any) {
        guard let req = parse(body: body) else {
            return
        }

        let normalized = normalizedAction(from: req.action)
        lastAction = normalized

        switch normalized {
        case "GET_MESH_STATE":
            Task { @MainActor in
                await handleGetMesh(requestID: req.requestID)
            }
        case "GET_PROJECTION":
            Task { @MainActor in
                await handleProjection(requestID: req.requestID)
            }
        case "SWAP_CELL":
            Task { @MainActor in
                await handleSwap(request: req)
            }
        case "HEAL_CELL":
            Task { @MainActor in
                await handleHeal(request: req)
            }
        case "ENGAGE_IGNITION":
            Task { @MainActor in
                await handleEngageIgnition(request: req)
            }
        case "SET_VIEWPORT_PLANT":
            let kind = req.raw["plant_kind"] ?? ""
            onViewportPlantKind?(kind)
            sendDirect(
                action: "set_viewport_plant",
                data: ["ok": true, "plant_kind": kind],
                requestID: req.requestID
            )
            emitSignedTransitionReceipts(
                for: "SET_VIEWPORT_PLANT",
                requestID: req.requestID,
                context: ["plant_kind": kind],
                description: "viewport plant kind forwarded to native OpenUSD",
                eversionGated: true,
                expectedPlantKindForGate: kind
            )
        case "MUTATE_VARIANT":
            Task { @MainActor in
                await handleMutateVariant(request: req)
            }
        case "NAV_INTENT":
            sendDirect(
                action: "nav_intent",
                data: [
                    "ok": true,
                    "target": req.raw["target"] ?? "grid",
                    "message": "nav intent acknowledged",
                ],
                requestID: req.requestID,
            )
            emitSignedTransitionReceipts(
                for: normalized,
                requestID: req.requestID,
                context: ["target": req.raw["target"] ?? "grid"],
                description: "NAV_INTENT acknowledged",
            )
        case "SELECT_CELL":
            applyRemoteCellSelection?(req.cellID)
            sendDirect(
                action: "select_cell",
                data: [
                    "ok": true,
                    "cell_id": req.cellID ?? "",
                    "message": "SELECT_CELL acknowledged",
                ],
                requestID: req.requestID,
            )
            emitSignedTransitionReceipts(
                for: normalized,
                requestID: req.requestID,
                context: ["cell_id": req.cellID ?? ""],
                description: "SELECT_CELL acknowledged",
            )
        case "RUN_MATRIX":
            sendDirect(action: "RUN_MATRIX", data: ["ok": true, "message": "run_matrix acknowledged"], requestID: req.requestID)
            let cyclesValue = req.raw["cycles"] ?? "n/a"
            emitSignedTransitionReceipts(
                for: normalized,
                requestID: req.requestID,
                context: ["cycles": cyclesValue],
                description: "run_matrix intent acknowledged",
            )
        case "REFRESH_S4":
            sendDirect(action: "PROJECTION_UPDATE", data: ["ok": true], requestID: req.requestID)
            emitSignedTransitionReceipts(
                for: normalized,
                requestID: req.requestID,
                context: ["action": "REFRESH_S4"],
                description: "refresh_s4 acknowledged",
            )
        default:
            sendDirect(
                action: "ERROR",
                data: ["error": "unknown_action", "action": req.action, "normalized_action": normalized],
                requestID: req.requestID,
            )
        }
    }

    private func parse(body: Any) -> BridgeRequest? {
        guard let dict = body as? [String: Any] else {
            if let raw = body as? String,
               let data = raw.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return parse(dict: parsed)
            }
            return nil
        }
        return parse(dict: dict)
    }

    private func parse(dict: [String: Any]) -> BridgeRequest? {
        guard let action = dict["action"] as? String else {
            return nil
        }
        let requestID = (dict["request_id"] as? String) ?? UUID().uuidString
        var raw: [String: String] = [:]
        for (key, value) in dict {
            switch value {
            case let text as String:
                raw[key] = text
            case let bool as Bool:
                raw[key] = String(bool)
            case let int as Int:
                raw[key] = String(int)
            case let double as Double:
                raw[key] = String(double)
            default:
                raw["\(key)"] = raw["\(key)"] ?? ""
            }
        }
        return BridgeRequest(
            action: action,
            requestID: requestID,
            cellID: dict["cell_id"] as? String,
            inputPlantType: dict["input"] as? String,
            outputPlantType: dict["output"] as? String,
            raw: raw
        )
    }

    private func handleGetMesh(requestID: String) async {
        await meshManagerRef?.refresh()
        guard let meshManager = meshManagerRef else {
            sendDirect(
                action: "get_mesh_state",
                data: ["error": "mesh_manager_unavailable"],
                requestID: requestID,
            )
            return
        }
        let cells = meshManager.cells.map { cell in
            [
                "id": cell.id,
                "name": cell.name,
                "ipv4": cell.ipv4,
                "role": cell.role,
                "health": cell.health,
                "status": cell.status,
                "input": cell.inputPlantType.rawValue,
                "output": cell.outputPlantType.rawValue,
                "active": cell.active,
            ]
        }
        let traceArmed = (traceModeProvider?() == true) || operatorControlsArmed
        sendDirect(
            action: "get_mesh_state",
            data: [
                "mesh": cells,
                "healthy": meshManager.healthyCount,
                "total": meshManager.cells.count,
                "nats_connected": meshManager.natsConnected,
                "v_qbit": meshManager.vQbit,
                "control_matrix": [
                    "trace_active": traceArmed,
                    "nats_connected": meshManager.natsConnected,
                    "swap_ready": meshManager.healthyCount >= 5,
                ],
            ],
            requestID: requestID,
        )
    }

    private func handleProjection(requestID: String) async {
        await meshManagerRef?.refresh()
        guard let meshManager = meshManagerRef else {
            sendDirect(
                action: "get_projection",
                data: ["error": "mesh_manager_unavailable"],
                requestID: requestID,
            )
            return
        }
        let projection = meshManager.projectionPayload()
        let cells = meshManager.cells.map { cellState(for: $0) }
        sendDirect(
            action: "get_projection",
            data: [
                "projection_s4": [
                    "mesh": [
                        "healthy": projection.meshHealthy,
                        "total": projection.meshTotal,
                        "cells": cells,
                    ],
                    "v_qbit": projection.vqbitDelta,
                    "nats_connected": projection.natsConnected,
                ],
                "flow_catalog_s4": [
                    "production_systems": ["plasma", "nats", "mesh", "control_surface"],
                    "virtual_systems": ["proxy", "vault", "ingress"],
                ],
                "production_systems_ui": [
                    "mesh_health": projection.meshHealthText,
                    "v_qbit": projection.vqbitText,
                ],
                "long_run": [
                    "running": false,
                    "jsonl_tail_line_count": projection.swapsRecent.count,
                ],
                "control_matrix": [
                    "swap_ready": meshManager.healthyCount >= 5,
                    "v_qbit_delta": projection.vqbitDelta,
                    "trace_active": (traceModeProvider?() == true) || operatorControlsArmed,
                ],
            ],
            requestID: requestID,
        )
    }

    private func cellState(for cell: CellState) -> [String: Any] {
        [
            "id": cell.id,
            "name": cell.name,
            "ipv4": cell.ipv4,
            "role": cell.role,
            "health": cell.health,
            "status": cell.status,
            "input": cell.inputPlantType.rawValue,
            "output": cell.outputPlantType.rawValue,
            "active": cell.active,
        ]
    }

    private func projectionBody(_ projection: ProjectionState) -> [String: Any] {
        let cells = meshManagerRef?.cells.map { cellState(for: $0) } ?? []
        return [
            "projection_s4": [
                "mesh": [
                    "healthy": projection.meshHealthy,
                    "total": projection.meshTotal,
                    "cells": cells,
                ],
                "v_qbit": projection.vqbitDelta,
                "nats_connected": projection.natsConnected,
                "updated_at": projection.lastUpdatedUtc,
            ],
            "flow_catalog_s4": [
                "production_systems": ["fusion", "mesh", "nats", "bridge"],
                "virtual_systems": ["proxy", "vault", "analytics"],
            ],
            "production_systems_ui": [
                "mesh_health": projection.meshHealthText,
                "healthy_cells": projection.meshHealthy,
                "total_cells": projection.meshTotal,
            ],
            "long_run": [
                "running": false,
                "record_count": projection.swapsRecent.count,
                "last_updated": projection.lastUpdatedUtc,
            ],
            "control_matrix": [
                "trace_active": (traceModeProvider?() == true) || operatorControlsArmed,
            ],
        ]
    }

    private func handleSwap(request: BridgeRequest) async {
        guard let meshManager = meshManagerRef else {
            sendDirect(
                action: "swap_cell",
                data: ["ok": false, "error": "mesh_manager_unavailable"],
                requestID: request.requestID
            )
            emitSignedTransitionReceipts(
                for: "SWAP_CELL",
                requestID: request.requestID,
                context: ["cell_id": request.cellID ?? "", "status": "mesh_manager_unavailable"],
                description: "SWAP_CELL blocked: mesh manager unavailable",
            )
            return
        }
        guard let cellID = request.cellID, !cellID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendDirect(
                action: "swap_cell",
                data: [
                    "ok": false,
                    "error": "ERR_MISSING_EXPLICIT_TARGET",
                    "message": "SWAP_CELL requires explicit cell_id; implicit target resolution is disabled.",
                ],
                requestID: request.requestID
            )
            emitSignedTransitionReceipts(
                for: "SWAP_CELL",
                requestID: request.requestID,
                context: ["cell_id": "", "status": "ERR_MISSING_EXPLICIT_TARGET"],
                description: "SWAP_CELL blocked: missing explicit target",
            )
            return
        }
        let rawInput = request.inputPlantType ?? ""
        let rawOutput = request.outputPlantType ?? ""
        if let precheck = meshManager.precheckSwap(
            traceActive: traceModeProvider?() == true,
            cellID: cellID,
            input: rawInput,
            output: rawOutput
        ) {
            sendDirect(
                action: "swap_cell",
                data: ["ok": false, "error": precheck.rawValue],
                requestID: request.requestID
            )
            emitSignedTransitionReceipts(
                for: "SWAP_CELL",
                requestID: request.requestID,
                context: ["cell_id": cellID, "status": precheck.rawValue],
                description: "SWAP_CELL blocked: \(precheck.rawValue)",
            )
            return
        }
        let inputPlant = PlantType.normalized(raw: rawInput)
        let outputPlant = PlantType.normalized(raw: rawOutput)

        let result = meshManager.requestSwap(cellID: cellID, input: inputPlant.rawValue, output: outputPlant.rawValue)
        sendDirect(
            action: "swap_cell",
            data: [
                "ok": result.success,
                "request_id": result.requestID,
                "message": result.message,
                "cell_identity_hash": identityHashProvider?() ?? "unverified",
                "detail": [
                    "cell_id": cellID,
                    "input": inputPlant,
                    "output": outputPlant,
                ],
            ],
            requestID: request.requestID,
        )
        emitSignedTransitionReceipts(
            for: "SWAP_CELL",
            requestID: request.requestID,
            context: [
                "cell_id": cellID,
                "input": inputPlant,
                "output": outputPlant,
                "result": result.success,
            ],
            description: result.success ? "SWAP_CELL completed" : "SWAP_CELL failed",
        )
    }

    private func handleHeal(request: BridgeRequest) async {
        guard let meshManager = meshManagerRef else {
            sendDirect(
                action: "heal_cell",
                data: ["ok": false, "error": "mesh_manager_unavailable"],
                requestID: request.requestID
            )
            emitSignedTransitionReceipts(
                for: "HEAL_CELL",
                requestID: request.requestID,
                context: ["status": "mesh_manager_unavailable"],
                description: "HEAL_CELL blocked: mesh manager unavailable",
            )
            return
        }
        if let precheck = meshManager.precheckTraceForMutation(traceActive: traceModeProvider?() == true) {
            sendDirect(
                action: "heal_cell",
                data: ["ok": false, "error": precheck.rawValue, "message": "Trace layer must be active for heal actions."],
                requestID: request.requestID
            )
            emitSignedTransitionReceipts(
                for: "HEAL_CELL",
                requestID: request.requestID,
                context: ["status": precheck.rawValue],
                description: "HEAL_CELL blocked: trace layer inactive",
            )
            return
        }
        guard let target = request.cellID ?? resolveTargetCellID() else {
            sendDirect(
                action: "heal_cell",
                data: ["ok": false, "error": "missing_cell_id"],
                requestID: request.requestID
            )
            emitSignedTransitionReceipts(
                for: "HEAL_CELL",
                requestID: request.requestID,
                context: ["status": "missing_cell_id"],
                description: "HEAL_CELL blocked: missing cell id",
            )
            return
        }
        let keyPath = UserDefaults.standard.string(forKey: "fusion_ssh_key_path") ?? ""
        let user = UserDefaults.standard.string(forKey: "fusion_ssh_user") ?? "root"
        if keyPath.isEmpty {
            sendDirect(
                action: "heal_cell",
                data: [
                    "ok": false,
                    "message": "ssh key not configured",
                    "detail": ["user": user, "cell": target],
                ],
                requestID: request.requestID,
            )
            emitSignedTransitionReceipts(
                for: "HEAL_CELL",
                requestID: request.requestID,
                context: ["status": "ssh_key_missing", "cell": target],
                description: "HEAL_CELL blocked: SSH key not configured",
            )
            return
        }

        let (exitCode, snippet) = await runShell(
            [
                "ssh",
                "-i",
                keyPath,
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=5",
                "\(user)@\(target)",
                "sudo",
                "systemctl",
                "restart",
                "gaiaftcl-wallet-gate",
            ]
        )

        sendDirect(
            action: "heal_cell",
            data: [
                "ok": exitCode == 0,
                "target": target,
                "cell_identity_hash": identityHashProvider?() ?? "unverified",
                "exit_code": exitCode,
                "snippet": snippet,
            ],
            requestID: request.requestID,
        )
        emitSignedTransitionReceipts(
            for: "HEAL_CELL",
            requestID: request.requestID,
            context: ["target": target, "exit_code": exitCode],
            description: exitCode == 0 ? "HEAL_CELL completed" : "HEAL_CELL failed",
        )
    }

    private func handleEngageIgnition(request: BridgeRequest) async {
        guard let meshManager = meshManagerRef else {
            sendDirect(
                action: "engage_ignition",
                data: ["ok": false, "error": "mesh_manager_unavailable"],
                requestID: request.requestID
            )
            emitSignedTransitionReceipts(
                for: "ENGAGE_IGNITION",
                requestID: request.requestID,
                context: ["status": "mesh_manager_unavailable"],
                description: "ENGAGE_IGNITION blocked: mesh manager unavailable",
            )
            return
        }
        let target = request.cellID ?? resolveTargetCellID()
        sendDirect(
            action: "engage_ignition",
            data: [
                "ok": true,
                "intent": "ENGAGE_IGNITION",
                "cell_identity_hash": identityHashProvider?() ?? "unverified",
                "target": target ?? "",
                "mesh_count": meshManager.cells.count,
            ],
            requestID: request.requestID,
        )
        emitSignedTransitionReceipts(
            for: "ENGAGE_IGNITION",
            requestID: request.requestID,
            context: [
                "target": target ?? "",
                "mesh_count": meshManager.cells.count,
            ],
            description: "ENGAGE_IGNITION executed",
        )
        onEngageIgnitionPlayback?()
    }

    private func handleMutateVariant(request: BridgeRequest) async {
        guard let meshManager = meshManagerRef else {
            sendDirect(
                action: "mutate_variant",
                data: ["ok": false, "error": "mesh_manager_unavailable"],
                requestID: request.requestID
            )
            emitSignedTransitionReceipts(
                for: "MUTATE_VARIANT",
                requestID: request.requestID,
                context: ["status": "mesh_manager_unavailable"],
                description: "MUTATE_VARIANT blocked: mesh manager unavailable",
            )
            return
        }

        let variant = request.raw["variantId"]
            ?? request.raw["variant_id"]
            ?? request.raw["locale"]
            ?? "en-US"
        await meshManager.refresh()
        let projection = meshManager.projectionPayload()

        sendDirect(
            action: "PROJECTION_UPDATE",
            data: [
                "projection": projectionBody(projection),
                "variantId": variant,
            ],
            requestID: request.requestID,
        )
        sendDirect(
            action: "mutate_variant",
            data: [
                "ok": true,
                "variant_id": variant,
                "cell_identity_hash": identityHashProvider?() ?? "unverified",
            ],
            requestID: request.requestID,
        )
        emitSignedTransitionReceipts(
            for: "MUTATE_VARIANT",
            requestID: request.requestID,
            context: [
                "variant": variant,
                "projection_mesh_healthy": projection.meshHealthy,
                "projection_mesh_total": projection.meshTotal,
            ],
            description: "MUTATE_VARIANT executed",
        )
    }

    private func resolveTargetCellID() -> String? {
        meshManagerRef?.cells
            .first(where: { $0.active })?
            .id
        ?? meshManagerRef?.cells
            .sorted { $0.id < $1.id }
            .first?
            .id
    }

    private func runShell(_ args: [String]) async -> (Int, String) {
        await withCheckedContinuation { cont in
            processQueue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: args.first ?? "ssh")
                process.arguments = Array(args.dropFirst())
                let out = Pipe()
                process.standardOutput = out
                process.standardError = out
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8) ?? ""
                    cont.resume(returning: (Int(process.terminationStatus), text))
                } catch {
                    cont.resume(returning: (127, String(describing: error)))
                }
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // WASM Constitutional Integration
    // ═══════════════════════════════════════════════════════════════
    
    /// Call WASM constitutional_check via WKWebView and update layout
    func checkConstitutional(i_p: Double, b_t: Double, n_e: Double, plantKind: UInt32 = 0) {
        guard let webView = webViewRef else { return }
        
        let js = """
        (async () => {
            try {
                const mod = await import('/api/fusion/wasm-substrate-bindgen.js');
                const violationCode = mod.constitutional_check(\(i_p), \(b_t), \(n_e));
                const terminalState = mod.compute_vqbit(0.5, 0.8, \(plantKind));
                const residual = mod.compute_closure_residual(\(i_p), \(b_t), \(n_e), \(plantKind));
                return {
                    violation_code: violationCode,
                    terminal_state: terminalState,
                    closure_residual: residual,
                    ts_ms: Date.now()
                };
            } catch (e) {
                return {
                    error: String(e),
                    violation_code: 255,
                    terminal_state: 2,
                    closure_residual: 999.0
                };
            }
        })();
        """
        
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("WASM constitutional check failed: \(error)")
                return
            }
            
            guard let dict = result as? [String: Any],
                  let violationCode = dict["violation_code"] as? NSNumber,
                  let terminalState = dict["terminal_state"] as? NSNumber,
                  let residual = dict["closure_residual"] as? Double else {
                print("Invalid WASM result format")
                return
            }
            
            // Update layout manager
            self.layoutManager?.updateFromWasm(
                violationCode: violationCode.uint8Value,
                terminalState: terminalState.uint8Value,
                closureResidual: residual
            )
            
            // Wire to state machine (Phase 5): Force constitutional alarm on critical violations
            // Note: Alarm exit requires operator acknowledgment (L2) per 21 CFR Part 11 §11.200
            // WASM cannot self-clear the alarm — that would bypass required human authorization
            let violationCodeValue = violationCode.uint8Value
            if violationCodeValue >= 4 {
                self.fusionCellStateMachine?.forceState(.constitutionalAlarm)
            }
            
            // Send result to WKWebView for dashboard display
            self.sendDirect(
                action: "CONSTITUTIONAL_CHECK_RESULT",
                data: [
                    "violation_code": violationCode,
                    "terminal_state": terminalState,
                    "closure_residual": residual,
                    "i_p": i_p,
                    "b_t": b_t,
                    "n_e": n_e,
                ],
                requestID: UUID().uuidString
            )
        }
    }
    
    /// Periodic WASM constitutional monitoring (called from NATS telemetry updates)
    func monitorConstitutionalState(telemetry: [String: Double]) {
        let i_p = telemetry["I_p"] ?? 0.0
        let b_t = telemetry["B_T"] ?? 0.0
        let n_e = telemetry["n_e"] ?? 0.0
        
        // Only check if values are present and non-zero
        guard i_p > 0 || b_t > 0 || n_e > 0 else { return }
        
        checkConstitutional(i_p: i_p, b_t: b_t, n_e: n_e)
    }
}
