import Darwin
import Foundation
@preconcurrency import Swifter

private final class SendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class HttpResponseBox: @unchecked Sendable {
    var value: HttpResponse!
}

private final class DevProxyResponse: @unchecked Sendable {
    var status: Int
    var headers: [String: String]
    var data: Data

    init(status: Int = 502, headers: [String: String] = ["Content-Type": "text/plain"], data: Data = Data("dev proxy unavailable".utf8)) {
        self.status = status
        self.headers = headers
        self.data = data
    }
}

/// Swifter invokes route handlers on a background GCD queue. Mirror dev-proxy / bound-port fields here so
/// `nonisolated` response paths never read `@MainActor` storage from Thread 15 (Swift 6 isolation trap).
private final class HTTPServingState: @unchecked Sendable {
    private let lock = NSLock()
    private var isDevMode = true
    private var isProxyHealthy = true
    private var devProxyPort = 3000
    private var boundPort = 8910

    func update(isDevMode: Bool? = nil, isProxyHealthy: Bool? = nil, devProxyPort: Int? = nil, boundPort: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let v = isDevMode { self.isDevMode = v }
        if let v = isProxyHealthy { self.isProxyHealthy = v }
        if let v = devProxyPort { self.devProxyPort = v }
        if let v = boundPort { self.boundPort = v }
    }

    func read() -> (isDevMode: Bool, isProxyHealthy: Bool, devProxyPort: Int, boundPort: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (isDevMode, isProxyHealthy, devProxyPort, boundPort)
    }
}

extension HttpServer: @retroactive @unchecked Sendable {}

/// UI/published state is MainActor; Swifter handlers run on a background queue — mesh/bridge routes use
/// `httpResponseOnMainActor`, fusion surface + static responses use `HTTPServingState` + `nonisolated` helpers.
@MainActor
final class LocalServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isDevMode = true
    @Published private(set) var boundPort = 8910

    /// Swifter server handle — `HttpServer` is `Sendable`; `bindTCPListen()` runs off the MainActor.
    private let server = HttpServer()
    /// Thread-safe port/mode mirror — Swifter reads this from background sockets without touching `@MainActor` storage.
    nonisolated(unsafe) private let httpServingState = HTTPServingState()
    /// Set in `prepareHTTPStack()` before `bindTCPListen()` runs concurrently.
    nonisolated(unsafe) private var pendingBindPort: UInt16 = 8910
    private var started = false
    private var isProxyHealthy = true
    private var proxyFailureCount = 0
    private let proxyFailureThreshold = 3
    private let proxyRecoveryTick: UInt64 = 2_000_000_000
    private var recoveryTask: DispatchSourceTimer?
    /// True while the background timer is re-probing upstream `next dev` and `fusion-s4` (self-heal loop).
    private var upstreamRecoveryActive = false
    private let recoveryQueue = DispatchQueue(label: "gaiafusion.proxy.recovery", qos: .utility)
    private let bridgeStatus = BridgeStatus()
    private weak var meshManager: MeshStateManager?
    weak var fusionBridge: FusionBridge?
    /// OpenUSD / Metal playback snapshot (`OpenUSDPlaybackController.jsonSnapshot()`).
    var openUSDPlaybackProvider: (() -> [String: Any])?
    /// Splash epistemics for `/api/fusion/self-probe` — wired from `AppCoordinator` (`splash_dismissed`, `splash_dismiss_reason`).
    var splashStateProvider: (() -> [String: Any])?
    /// Loopback gate: same path as WKWebView `SET_VIEWPORT_PLANT` / MCP `set_plant_payload` — drives OpenUSD plant swap without UI.
    var loadViewportPlantHook: ((String) -> Void)?
    /// Loopback gate: same as bridge `onEngageIgnitionPlayback` — ENGAGE for timeline / normalized_t kinematic proofs.
    var engageViewportHook: (() -> Void)?
    /// Upstream Next.js `next dev` port (never the same as `boundPort` — GaiaFusion owns the WebView origin).
    private var devProxyPort: Int = 3000
    private let uiPortOverride: Int?
    var identityHashProvider: (() -> String?)?
    var traceActiveProvider: (() -> Bool)?
    /// MCP / head: loopback visibility + NATS subjects (`AppCoordinator.mcpCellCommsSnapshot`).
    var mcpCommsProvider: (() -> [String: Any])?
    /// Fire-and-forget async: publish one NATS presence snapshot (wired from `AppCoordinator`).
    var mcpPresencePingHandler: (() async -> Void)?
    /// Layout manager state snapshot for UI mode, opacity, constitutional HUD visibility.
    var layoutManagerProvider: (() -> [String: Any])?

    init(meshManager: MeshStateManager) {
        self.meshManager = meshManager
        self.identityHashProvider = nil
        self.uiPortOverride = ProcessInfo.processInfo.environment["FUSION_UI_PORT"]
            .flatMap { Int($0) }
    }

    @MainActor
    private func syncHTTPServingState() {
        httpServingState.update(
            isDevMode: isDevMode,
            isProxyHealthy: isProxyHealthy,
            devProxyPort: devProxyPort,
            boundPort: boundPort
        )
    }

    /// Swifter runs route bodies off the main thread; mesh + bridge live on `@MainActor`.
    nonisolated private func httpResponseOnMainActor(_ work: @MainActor () -> HttpResponse) -> HttpResponse {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(work)
        }
        let box = HttpResponseBox()
        DispatchQueue.main.sync {
            box.value = MainActor.assumeIsolated(work)
        }
        return box.value
    }

    /// Picks a port where `next dev` is actually listening. `npm run dev:fusion` defaults to 8910, which collides with GaiaFusion’s default UI port — companion dev should use another port (typically 3000).
    private static func detectDevProxyPort(excludingLocalPort: Int) -> Int {
        let candidates = [3000, 3001, 3002, 8911, 8912, 5173, 8080]
            .filter { $0 > 0 && $0 != excludingLocalPort }
        for port in candidates {
            if Self.nextFusionSurfaceResponds(port: port) {
                print("GaiaFusion: detected Next dev server on 127.0.0.1:\(port) (fusion-s4)")
                return port
            }
        }
        print("GaiaFusion: no Next dev server found on candidate ports; defaulting dev proxy to 3000")
        return 3000
    }

    private static func nextFusionSurfaceResponds(port: Int) -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/fusion-s4") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.45
        let sem = DispatchSemaphore(value: 0)
        let ok = SendableBox(false)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                ok.value = (200 ... 399).contains(http.statusCode)
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 0.6)
        return ok.value
    }

    func setBridgeLoaded(_ loaded: Bool) {
        bridgeStatus.webviewLoaded = loaded
    }

    /// Port selection, route wiring, embedded assets — must run on MainActor before any HTTP accept loop.
    func prepareHTTPStack() {
        guard !started else {
            return
        }
        started = true

        boundPort = UserDefaults.standard.integer(forKey: "fusion_ui_port")
        if boundPort <= 0 {
            boundPort = 8910
        }
        if let override = uiPortOverride, override > 0, override <= 65535 {
            boundPort = override
        }
        // Must use bool(forKey:) so `register(defaults:)` applies; `object(...) ?? true` ignored the registered false.
        isDevMode = UserDefaults.standard.bool(forKey: "fusion_dev_mode")

        if let explicit = ProcessInfo.processInfo.environment["FUSION_UI_PROXY_PORT"].flatMap({ Int($0) }),
           explicit > 0, explicit <= 65535 {
            devProxyPort = explicit
        } else {
            // `detectDevProxyPort` uses URLSession + semaphore; must not run on MainActor — completion can be
            // scheduled on the main queue and deadlock with `sem.wait` during app init.
            let exclude = Int(boundPort)
            var picked = 3000
            DispatchQueue.global(qos: .utility).sync {
                picked = Self.detectDevProxyPort(excludingLocalPort: exclude)
            }
            devProxyPort = picked
        }

        configureRoutes()

        // Archive expansion can invoke `tar`/`ditto` and block for minutes — must not run before Swifter listens or gate/headless probes stall.
        Task { @MainActor in
            FusionEmbeddedAssetGate.materializeEmbeddedArchiveIfNeeded()
        }

        syncHTTPServingState()
        pendingBindPort = UInt16(boundPort)
    }

    /// Swifter TCP bind — **nonisolated** so it can run on `DispatchQueue.global` without waiting for MainActor / NSApplication pump.
    nonisolated func bindTCPListen() {
        let port = pendingBindPort
        let devMode = UserDefaults.standard.bool(forKey: "fusion_dev_mode")
        do {
            try server.start(port, forceIPv4: true)
            let bootedAt = Date().timeIntervalSince1970
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.serverStartAt = bootedAt
                self.isRunning = true
                self.isProxyHealthy = true
                self.proxyFailureCount = 0
                self.syncHTTPServingState()
            }
            print("GaiaFusion server on 127.0.0.1:\(port) \(devMode ? "(dev proxy)" : "(static)")")
            fflush(stdout)
            fflush(stderr)
            McpLoopbackCommsServer.startIfConfigured()
        } catch {
            let errorMessage = (error as NSError).localizedDescription
            print("GaiaFusion failed to start on 127.0.0.1:\(port): \(errorMessage)")
            fflush(stdout)
            fflush(stderr)
            Task { @MainActor [weak self] in
                self?.isRunning = false
            }
        }
    }

    /// XCTest / single-threaded callers: prepare + bind on the current actor.
    func start() {
        prepareHTTPStack()
        bindTCPListen()
    }

    func stop() {
        McpLoopbackCommsServer.stop()
        server.stop()
        recoveryTask?.cancel()
        recoveryTask = nil
        upstreamRecoveryActive = false
        isRunning = false
    }

    private func configureRoutes() {
        server.GET["/api/fusion/health"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let kb = FusionEmbeddedAssetGate.witness()
                let wasm = self.fusionBridge?.wasmSurfacePayloadForHealth() ?? [
                    "schema": "gaiaftcl_wasm_dom_surface_v1",
                    "monitoring": false,
                    "closed": false,
                    "note": "fusion bridge not linked to LocalServer",
                ]
                let wasmClosed = (wasm["closed"] as? Bool) ?? false
                let wasmRuntime = self.fusionBridge?.wasmRuntimePayloadForHealth() ?? [
                    "schema": "gaiaftcl_wasm_runtime_v1",
                    "closed": false,
                    "note": "fusion bridge not linked to LocalServer",
                ]
                let wasmRuntimeClosed = (wasmRuntime["closed"] as? Bool) ?? false
                let cellStack = FusionSidecarCellBundle.healthPayload()
                let usdPx = ["status": "rust_renderer_active"]
                let openusdPlayback = self.openUSDPlaybackProvider?() ?? [
                    "schema": "gaiaftcl_openusd_playback_v1",
                    "note": "openUSDPlaybackProvider not wired",
                ]
                let layoutManager = self.layoutManagerProvider?() ?? [
                    "schema": "gaiaftcl_layout_manager_v1",
                    "note": "layoutManagerProvider not wired",
                ]
                let payload: [String: Any] = [
                    "status": "ok",
                    "pid": ProcessInfo.processInfo.processIdentifier,
                    "uptime_sec": max(0.0, Date().timeIntervalSince1970 - (self.serverStartAt ?? Date().timeIntervalSince1970)),
                    "v_qbit": self.meshManager?.vQbit ?? 0.0,
                    "v_qbit_projection": "local_mesh_ratio",
                    "v_qbit_note": "Healthy mesh nodes / \(MeshStateManager.MeshConstants.meshNodeCount) (fleet + Mac leaf); not Arango vqbit_measurements unless gateway-ingested.",
                    "mesh_nodes_total": MeshStateManager.MeshConstants.meshNodeCount,
                    "mode": self.isDevMode ? "dev_proxy" : "static",
                    "dev_proxy_port": self.devProxyPort,
                    "local_ui_port": self.boundPort,
                    "dev_proxy_healthy": self.isProxyHealthy,
                    "dev_proxy_failures": self.proxyFailureCount,
                    "self_heal": [
                        "recovery_active": self.upstreamRecoveryActive,
                        "reprobe_upstream_allowed": ProcessInfo.processInfo.environment["FUSION_UI_PROXY_PORT"] == nil,
                    ],
                    "klein_bottle": kb.jsonObject,
                    "klein_bottle_closed": kb.kleinBottleClosed,
                    "wasm_surface": wasm,
                    "wasm_surface_closed": wasmClosed,
                    "wasm_runtime": wasmRuntime,
                    "wasm_runtime_closed": wasmRuntimeClosed,
                    "trace_active": self.traceActiveProvider?() == true,
                    "cell_stack": cellStack,
                    "usd_px": usdPx,
                    "openusd_playback": openusdPlayback,
                    "layout_manager": layoutManager,
                    "mcp_cell": self.mcpCommsProvider?() ?? [
                        "schema": "gaiaftcl_mcp_cell_comms_v1",
                        "note": "mcpCommsProvider not wired",
                    ],
                ]
                return Self.jsonResponse(payload)
            }
        }

        server.GET["/api/fusion/mcp-cell"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let payload = self.mcpCommsProvider?() ?? [
                    "schema": "gaiaftcl_mcp_cell_comms_v1",
                    "terminal": "REFUSED",
                    "reason": "mcpCommsProvider not wired",
                ]
                return Self.jsonResponse(payload)
            }
        }

        server.POST["/api/fusion/mcp-cell/ping"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let handler = self.mcpPresencePingHandler
                Task {
                    await handler?()
                }
                let snap = self.mcpCommsProvider?() ?? [
                    "schema": "gaiaftcl_mcp_cell_comms_v1",
                    "terminal": "REFUSED",
                    "reason": "mcpCommsProvider not wired",
                ]
                return Self.jsonResponse([
                    "ok": true,
                    "schema": "gaiaftcl_mcp_cell_ping_v1",
                    "mcp_cell": snap,
                    "nats_presence_publish_scheduled": handler != nil,
                ])
            }
        }

        server.GET["/api/fusion/openusd-playback"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let snap = self.openUSDPlaybackProvider?() ?? [
                    "schema": "gaiaftcl_openusd_playback_v1",
                    "terminal": "REFUSED",
                    "reason": "openUSDPlaybackProvider_nil",
                ]
                return Self.jsonResponse(snap)
            }
        }

        server.GET["/api/fusion/bridge-status"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                return Self.jsonResponse([
                    "connected": true,
                    "webview_loaded": self.bridgeStatus.webviewLoaded,
                    "openusd_playback": self.openUSDPlaybackProvider?() ?? [:],
                ])
            }
        }

        /// Internal operator surface: WASM + sidecar + WKWebView DOM snapshot (in-app substitute for headless Playwright against loopback).
        server.GET["/api/fusion/self-probe"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            if Thread.isMainThread {
                let snapshotPort = self.httpServingState.read().boundPort
                let ts = ISO8601DateFormatter().string(from: Date())
                return Self.jsonResponse([
                    "schema": "gaiaftcl_fusion_self_probe_v1",
                    "ts_utc": ts,
                    "terminal": "REFUSED",
                    "reason": "self_probe_on_main_thread",
                    "local_ui_port": snapshotPort,
                    "note": "Swifter must run /api/fusion/self-probe off the main queue; retry from a background client",
                ])
            }
            let sem = DispatchSemaphore(value: 0)
            var captured: [String: Any] = [:]
            let ts = ISO8601DateFormatter().string(from: Date())
            let usdPx = ["status": "rust_renderer_active"]
            let snapshotPort = self.httpServingState.read().boundPort
            // Swifter runs on a background queue — all `@MainActor` reads must happen on the main executor.
            // Do **not** call `WKWebView.evaluateJavaScript` from inside `DispatchQueue.main.sync` entered from this
            // worker (WebKit / empty-reply risk). Use `main.async` + `MainActor.assumeIsolated`, then `sem.wait` here.
            // Also do **not** nest `Task { @MainActor in }` on `gaiafusion.localserver.selfprobe` (Swift 6 SIGTRAP).
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    guard let bridge = self.fusionBridge else {
                        var refused: [String: Any] = [
                            "schema": "gaiaftcl_fusion_self_probe_v1",
                            "ts_utc": ts,
                            "terminal": "REFUSED",
                            "reason": "fusion_bridge_nil",
                            "local_ui_port": self.boundPort,
                            "note": "FusionBridge not linked to LocalServer — full app only",
                            "usd_px": usdPx,
                        ]
                        if let s = self.splashStateProvider?() {
                            for (k, v) in s {
                                refused[k] = v
                            }
                        }
                        captured = refused
                        sem.signal()
                        return
                    }
                    var payload: [String: Any] = [
                        "schema": "gaiaftcl_fusion_self_probe_v1",
                        "ts_utc": ts,
                        "pid": ProcessInfo.processInfo.processIdentifier,
                        "local_ui_port": self.boundPort,
                        "fusion_surface": "native_swift",
                        "wasm_surface": bridge.wasmSurfacePayloadForHealth(),
                        "wasm_runtime": bridge.wasmRuntimePayloadForHealth(),
                        "cell_stack": FusionSidecarCellBundle.healthPayload(),
                        "bridge_webview_loaded": self.bridgeStatus.webviewLoaded,
                        "usd_px": usdPx,
                        "openusd_playback": self.openUSDPlaybackProvider?() ?? [:],
                    ]
                    if let s = self.splashStateProvider?() {
                        for (k, v) in s {
                            payload[k] = v
                        }
                    }
                    bridge.runInternalDomProbe { dom in
                        payload["dom_analysis"] = dom
                        payload["terminal"] = "CURE"
                        captured = payload
                        sem.signal()
                    }
                }
            }
            _ = sem.wait(timeout: .now() + 7.0)
            if captured.isEmpty {
                var splashFields: [String: Any] = [:]
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        if let s = self.splashStateProvider?() {
                            splashFields = s
                        }
                    }
                }
                var timeoutBody: [String: Any] = [
                    "schema": "gaiaftcl_fusion_self_probe_v1",
                    "ts_utc": ts,
                    "terminal": "REFUSED",
                    "reason": "self_probe_timeout",
                    "local_ui_port": snapshotPort,
                    "usd_px": usdPx,
                ]
                for (k, v) in splashFields {
                    timeoutBody[k] = v
                }
                captured = timeoutBody
            }
            return Self.jsonResponse(captured)
        }

        server.GET["/api/fusion/cells"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let cells = self.meshManager?.cells.map { cell in
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
                } ?? []
                return Self.jsonResponse(cells)
            }
        }

        server.GET["/api/fusion/plant-kinds"] = { _ in
            Self.jsonResponse([
                "schema": "gaiaftcl_fusion_plant_kinds_v1",
                "kinds": PlantKindsCatalog.shared.kinds,
                "count": PlantKindsCatalog.shared.kinds.count,
                "aliases": PlantKindsCatalog.kindAliases,
            ])
        }

        /// Same-origin WASM bytes for `WebAssembly.instantiateStreaming` — WKWebView `fetch` to `gaiasubstrate://` may fail; HTTP seam is C4 for the runtime gate.
        server.GET["/api/fusion/wasm-substrate"] = { _ in
            guard let url = Bundle.module.url(forResource: "gaiafusion_substrate", withExtension: "wasm"),
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty
            else {
                return HttpResponse.notFound
            }
            return HttpResponse.ok(HttpResponseBody.data(data, contentType: "application/wasm"))
        }

        /// wasm-bindgen glue (ES module) — pair with `gaiafusion_substrate.wasm` (`*_bg.wasm`); WKWebView `import()` loads this, then `default('/api/fusion/wasm-substrate')` completes instantiation.
        server.GET["/api/fusion/wasm-substrate-bindgen.js"] = { _ in
            guard let url = Bundle.module.url(forResource: "gaiafusion_substrate_bindgen", withExtension: "js"),
                  let data = try? Data(contentsOf: url),
                  !data.isEmpty
            else {
                return HttpResponse.notFound
            }
            return HttpResponse.ok(HttpResponseBody.data(data, contentType: "application/javascript"))
        }

        /// Substrate viewport (WASM shell iframe) — same-origin fetch from bundled `/substrate` HTML.
        /// Next.js dev routes proxy the gateway; embedded GaiaFusion must serve native mesh state here.
        server.GET["/api/substrate/health"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let healthy = self.meshManager?.healthyCount ?? 0
                let total = self.meshManager?.cells.count ?? 0
                let payload: [String: Any] = [
                    "status": "ok",
                    "source": "gaiafusion_local",
                    "note": "Embedded GaiaFusion LocalServer; mesh from native MeshStateManager (not web-host gateway proxy).",
                    "mesh": [
                        "healthy": healthy,
                        "total": total,
                    ],
                    "nats_connected": self.meshManager?.natsConnected ?? false,
                    "updated_at": ISO8601DateFormatter().string(from: Date()),
                ]
                return Self.jsonResponse(payload)
            }
        }

        server.GET["/api/substrate/state"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let healthy = self.meshManager?.healthyCount ?? 0
                let total = self.meshManager?.cells.count ?? 0
                let cells = self.meshManager?.cells.map { cell in
                    [
                        "id": cell.id,
                        "name": cell.name,
                        "health": cell.health,
                        "status": cell.status,
                        "active": cell.active,
                    ]
                } ?? []
                let payload: [String: Any] = [
                    "status": "ok",
                    "source": "gaiafusion_local",
                    "healthy": healthy,
                    "total": total,
                    "cells": cells,
                    "nats_connected": self.meshManager?.natsConnected ?? false,
                    "updated_at": ISO8601DateFormatter().string(from: Date()),
                ]
                return Self.jsonResponse(payload)
            }
        }

        server.POST["/api/fusion/swap"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            guard request.method == "POST" else {
                return Self.textResponse("method_not_allowed", code: 405)
            }
            let body = request.body
            let bodyData = Data(body)
            guard let payload = try? JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any] else {
                return Self.textResponse("bad_json", code: 400)
            }
            let cellID = (payload["cell_id"] as? String) ?? ""
            let input = (payload["input_plant_type"] as? String) ?? (payload["input"] as? String) ?? ""
            let output = (payload["output_plant_type"] as? String) ?? (payload["output"] as? String) ?? ""
            let normalizedInput = PlantType.normalized(raw: input)
            let normalizedOutput = PlantType.normalized(raw: output)
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                guard let manager = self.meshManager else {
                    return Self.jsonResponse(["ok": false, "error": "mesh_manager_unavailable"])
                }
                guard !cellID.isEmpty && !input.isEmpty && !output.isEmpty else {
                    return Self.jsonResponse(["ok": false, "error": "missing_fields"])
                }
                guard normalizedInput != .unknown && normalizedOutput != .unknown else {
                    return Self.jsonResponse(["ok": false, "error": "unsupported_plant_kind"])
                }
                let result = manager.requestSwap(
                    cellID: cellID,
                    input: normalizedInput.rawValue,
                    output: normalizedOutput.rawValue
                )
                return Self.jsonResponse([
                    "ok": result.success,
                    "request_id": result.requestID,
                    "message": result.message,
                    "cell_identity_hash": self.identityHashProvider?() ?? "unverified",
                ])
            }
        }

        server.POST["/api/fusion/gate/load-viewport-plant"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            let bodyData = Data(request.body)
            guard let payload = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let rawKind = payload["plant_kind"] as? String,
                  !rawKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return Self.jsonResponse([
                    "ok": false,
                    "schema": "gaiaftcl_gate_load_viewport_plant_v1",
                    "error": "bad_json_or_missing_plant_kind",
                ])
            }
            let resolved = PlantType.normalized(raw: rawKind)
            if resolved == .unknown {
                return Self.jsonResponse([
                    "ok": false,
                    "schema": "gaiaftcl_gate_load_viewport_plant_v1",
                    "error": "unsupported_plant_kind",
                    "plant_kind": rawKind,
                ])
            }
            let normalized = resolved.rawValue
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                guard let hook = self.loadViewportPlantHook else {
                    return Self.jsonResponse([
                        "ok": false,
                        "schema": "gaiaftcl_gate_load_viewport_plant_v1",
                        "error": "load_viewport_plant_hook_nil",
                    ])
                }
                hook(rawKind)
                return Self.jsonResponse([
                    "ok": true,
                    "schema": "gaiaftcl_gate_load_viewport_plant_v1",
                    "plant_kind": normalized,
                ])
            }
        }

        server.POST["/api/fusion/gate/engage-viewport"] = { [weak self] _ in
            guard let self else { return HttpResponse.internalServerError }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                guard let hook = self.engageViewportHook else {
                    return Self.jsonResponse([
                        "ok": false,
                        "schema": "gaiaftcl_gate_engage_viewport_v1",
                        "error": "engage_viewport_hook_nil",
                    ])
                }
                hook()
                return Self.jsonResponse([
                    "ok": true,
                    "schema": "gaiaftcl_gate_engage_viewport_v1",
                ])
            }
        }

        server.GET["/api/sovereign-mesh"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let cells = self.meshManager?.cells.map { cell in
                    [
                        "id": cell.id,
                        "name": cell.name,
                        "ipv4": cell.ipv4,
                        "status": cell.status,
                        "active": cell.active,
                        "health": cell.health,
                        "input": cell.inputPlantType.rawValue,
                        "output": cell.outputPlantType.rawValue,
                    ]
                } ?? []
                let payload: [String: Any] = [
                    "schema": "gaiaftcl_fusion_sovereign_mesh_v1",
                    "panels": [
                        "mesh_cells": cells,
                        "mesh_health": "\(self.meshManager?.healthyCount ?? 0)/\(self.meshManager?.cells.count ?? 0)",
                        "mesh_total": self.meshManager?.cells.count ?? 0,
                    ],
                    "nats_connected": self.meshManager?.natsConnected ?? false,
                    "v_qbit": self.meshManager?.vQbit ?? 0.0,
                    "v_qbit_projection": "local_mesh_ratio",
                    "v_qbit_note": "Healthy mesh nodes / \(MeshStateManager.MeshConstants.meshNodeCount) (fleet + Mac leaf); not Arango vqbit_measurements unless gateway-ingested.",
                    "mesh_nodes_total": MeshStateManager.MeshConstants.meshNodeCount,
                    "updated_at": ISO8601DateFormatter().string(from: Date()),
                    "fusion_surface": "native_swift",
                    "bundled_cell_compose_present": FusionSidecarCellBundle.bundledComposeURL() != nil,
                    "wasm_runtime_closed": (self.fusionBridge?.wasmRuntimePayloadForHealth()["closed"] as? Bool) ?? false,
                ]
                return Self.jsonResponse(payload)
            }
        }

        server.GET["/api/fusion/fleet-digest"] = { [weak self] _ in
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let cells = self.meshManager?.cells.map { cell in
                    [
                        "id": cell.id,
                        "name": cell.name,
                        "active": cell.active,
                    ]
                } ?? []
                let payload: [String: Any] = [
                    "schema": "gaiaftcl_fleet_digest_v1",
                    "mesh": [
                        "healthy": self.meshManager?.healthyCount ?? 0,
                        "total": self.meshManager?.cells.count ?? 0,
                    ],
                    "cells": cells,
                    "updated_at": ISO8601DateFormatter().string(from: Date()),
                ]
                return Self.jsonResponse(payload)
            }
        }

        server.GET["/api/fusion/s4-projection"] = { [weak self] _ in
            // Swifter invokes handlers on a background queue; MeshStateManager is @MainActor. Automated gate sets
            // GAIAFUSION_GATE_MINIMAL_S4=1 to return a deterministic JSON payload without cross-actor work (avoids
            // stalls when AppKit/Metal holds the main thread).
            if Self.gateMinimalS4ProjectionEnabled() {
                let projection = ProjectionState(
                    meshHealthy: 0,
                    meshTotal: MeshStateManager.MeshConstants.meshNodeCount,
                    natsConnected: false,
                    vqbitDelta: 0.0,
                    lastUpdatedUtc: ISO8601DateFormatter().string(from: Date()),
                    swapsRecent: []
                )
                let payload = Self.fusionProjectionPayloadValues(from: projection, traceActive: false)
                return Self.jsonHttpResponse(payload)
            }
            guard let self else {
                return HttpResponse.internalServerError
            }
            return self.httpResponseOnMainActor { [weak self] in
                guard let self else {
                    return HttpResponse.internalServerError
                }
                let projection = self.meshManager?.projectionPayload()
                    ?? ProjectionState(
                        meshHealthy: 0,
                        meshTotal: MeshStateManager.MeshConstants.meshNodeCount,
                        natsConnected: false,
                        vqbitDelta: 0.0,
                        lastUpdatedUtc: ISO8601DateFormatter().string(from: Date()),
                        swapsRecent: []
                    )
                let payload = self.fusionProjectionPayload(from: projection)
                return Self.jsonResponse(payload)
            }
        }

        server.GET["/fusion-s4"] = { [weak self] request in
            return self?.serveFusionSurface(request: request, fallbackPath: "/fusion-s4") ?? HttpResponse.internalServerError
        }

        server.GET["/fusion-s4/"] = { [weak self] request in
            return self?.serveFusionSurface(request: request, fallbackPath: "/fusion-s4/") ?? HttpResponse.internalServerError
        }

        server.GET["/fusion-s4/*"] = { [weak self] request in
            return self?.serveFusionSurface(request: request, fallbackPath: request.path) ?? HttpResponse.internalServerError
        }

        server.GET["/substrate"] = { [weak self] request in
            return self?.serveSubstrateViewport(request: request, fallbackPath: "/substrate") ?? HttpResponse.internalServerError
        }

        server.GET["/substrate/"] = { [weak self] request in
            return self?.serveSubstrateViewport(request: request, fallbackPath: "/substrate/") ?? HttpResponse.internalServerError
        }

        server.GET["/substrate/*"] = { [weak self] request in
            return self?.serveSubstrateViewport(request: request, fallbackPath: "/substrate" + request.path.replacingOccurrences(of: "/substrate", with: "")) ?? HttpResponse.internalServerError
        }

        server.GET["/substrate-raw"] = { [weak self] request in
            return self?.serveFusionSurface(request: request, fallbackPath: "/substrate-raw") ?? HttpResponse.internalServerError
        }

        server.GET["/substrate-raw/"] = { [weak self] request in
            return self?.serveFusionSurface(request: request, fallbackPath: "/substrate-raw/") ?? HttpResponse.internalServerError
        }

        server.GET["/substrate-raw/*"] = { [weak self] request in
            return self?.serveFusionSurface(request: request, fallbackPath: request.path) ?? HttpResponse.internalServerError
        }

        server.GET["/_next/*"] = { [weak self] request in
            return self?.serveFusionAsset(request: request) ?? HttpResponse.internalServerError
        }

        server.GET["/favicon.ico"] = { [weak self] request in
            return self?.serveFusionAsset(request: request) ?? HttpResponse.internalServerError
        }

        server.notFoundHandler = { [weak self] request in
            if let self {
                return self.serveFusionAsset(request: request)
            }
            return self?.serveFusionSurface(request: nil, fallbackPath: "/fusion-s4") ?? HttpResponse.notFound
        }
    }

    private var serverStartAt: TimeInterval? = nil

    private func fusionProjectionPayload(from projection: ProjectionState) -> [String: Any] {
        let traceChrome = traceActiveProvider?() == true
        let operatorArmed = bridgeStatus.webviewLoaded
        let traceActive = traceChrome || operatorArmed
        return Self.fusionProjectionPayloadValues(from: projection, traceActive: traceActive)
    }

    nonisolated private static func gateMinimalS4ProjectionEnabled() -> Bool {
        ProcessInfo.processInfo.environment["GAIAFUSION_GATE_MINIMAL_S4"] == "1"
    }

    nonisolated private static func fusionProjectionPayloadValues(from projection: ProjectionState, traceActive: Bool) -> [String: Any] {
        [
            "schema": "gaiaftcl_fusion_s4_projection_ui_v1",
            "projection_s4": [
                "mesh": [
                    "healthy": projection.meshHealthy,
                    "total": projection.meshTotal,
                ],
                "v_qbit": projection.vqbitDelta,
                "nats_connected": projection.natsConnected,
                "updated_at": projection.lastUpdatedUtc,
            ],
            "flow_catalog_s4": [
                "production_systems": ["fusion", "mesh", "nats", "control"],
                "virtual_systems": ["quantum_bridge", "portal", "vault"],
            ],
            "production_systems_ui": [
                "mesh_health": projection.meshHealthText,
                "healthy_cells": projection.meshHealthy,
                "total_cells": projection.meshTotal,
                "v_qbit": projection.vqbitDelta,
            ],
            "long_run": [
                "running": false,
                "record_count": projection.swapsRecent.count,
            ],
            "control_matrix": [
                "nats_connected": projection.natsConnected,
                "swap_ready": projection.meshHealthy >= 5,
                "v_qbit_delta": projection.vqbitDelta,
                "trace_active": traceActive,
            ],
        ]
    }

    nonisolated private static func jsonHttpResponse(_ value: Any) -> HttpResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return HttpResponse.raw(500, "Internal Server Error", ["Content-Type": "text/plain"]) { writer in
                try writer.write(Data("json encode failed".utf8))
            }
        }
        return HttpResponse.raw(200, "OK", ["Content-Type": "application/json"]) { writer in
            try writer.write(data)
        }
    }

    /// Swifter invokes this off the main actor; use `httpServingState` (not `@MainActor` fields) for mode/ports.
    nonisolated private func serveFusionSurface(request: HttpRequest?, fallbackPath: String) -> HttpResponse {
        let st = httpServingState.read()
        if st.isDevMode {
            guard st.isProxyHealthy else {
                if let fallback = serveStaticIfAvailableFallback(path: fallbackPath) {
                    return fallback
                }
                return Self.proxyDownResponse(fallbackPath: fallbackPath, devProxyPort: st.devProxyPort, boundPort: st.boundPort)
            }
            let proxyAttempt = proxyToDevServer(path: fallbackPath, request: request, devProxyPort: st.devProxyPort)
            if proxyAttempt.isSuccess {
                return proxyAttempt.response
            }
            // First proxy failure may still leave isProxyHealthy true (threshold not reached). Always prefer bundled static when available.
            if let fallback = serveStaticIfAvailableFallback(path: fallbackPath) {
                return fallback
            }
            return proxyAttempt.response
        }

        return serveStatic(path: fallbackPath)
    }

    private struct ProxyAttempt {
        let response: HttpResponse
        let isSuccess: Bool
    }

    nonisolated private func proxyToDevServer(path: String, request: HttpRequest?, devProxyPort: Int) -> ProxyAttempt {
        let target = "http://127.0.0.1:\(devProxyPort)\(path)"
        guard let url = URL(string: target) else {
            return ProxyAttempt(response: Self.textResponse("invalid proxy target", code: 500), isSuccess: false)
        }
        guard let req = request else {
            return ProxyAttempt(response: Self.textResponse("empty request", code: 400), isSuccess: false)
        }

        var proxy = URLRequest(url: url)
        proxy.httpMethod = req.method
        proxy.httpBody = req.body.isEmpty ? nil : Data(req.body)
        proxy.timeoutInterval = 1.5

        let sem = DispatchSemaphore(value: 0)
        let proxyResponse = DevProxyResponse()
        let requestErrorBox = SendableBox<Error?>(nil)

        let task = URLSession.shared.dataTask(with: proxy) { responseData, response, _ in
            proxyResponse.data = responseData ?? proxyResponse.data
            if let response = response as? HTTPURLResponse {
                proxyResponse.status = response.statusCode
                proxyResponse.headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                    result["\(item.key)"] = "\(item.value)"
                }
            }
            requestErrorBox.value = response == nil ? URLError(.badServerResponse) : nil
            sem.signal()
        }
        task.resume()
        let succeeded = sem.wait(timeout: .now() + 3) == .success
        let isSuccess = succeeded && requestErrorBox.value == nil && proxyResponse.status > 0
        if isSuccess {
            Task { @MainActor [weak self] in
                self?.markProxyRecovered()
            }
            return ProxyAttempt(
                response: .raw(proxyResponse.status, "", proxyResponse.headers, { writer in
                    try writer.write(proxyResponse.data)
                }),
                isSuccess: true
            )
        }

        Task { @MainActor [weak self] in
            self?.markProxyFailure()
            self?.startProxyRecovery()
        }
        let fallbackMessage = DevProxyResponse(
            status: 503,
            headers: ["Content-Type": "text/plain", "Cache-Control": "no-store"],
            data: Data("dev proxy unavailable, self-healing in progress".utf8),
        )
        return ProxyAttempt(
            response: .raw(fallbackMessage.status, "", fallbackMessage.headers, { writer in
                try writer.write(fallbackMessage.data)
            }),
            isSuccess: false
        )
    }

    nonisolated private func serveFusionAsset(request: HttpRequest) -> HttpResponse {
        let st = httpServingState.read()
        let query = request.queryParams.count > 0
            ? "?\(request.queryParams.map { "\($0.0)=\($0.1)" }.joined(separator: "&"))"
            : ""
        // Embedded app must always serve bundled `_next` assets locally to avoid proxy MIME drift.
        if Self.bundledFusionPath() != nil,
            request.path.hasPrefix("/_next") || request.path == "/favicon.ico" {
            return serveStatic(path: request.path)
        }
        // Bundled static export (fusion_dev_mode = false): never proxy — dev server is often absent and would 503 the iframe shells.
        if !st.isDevMode, Self.bundledFusionPath() != nil {
            return serveStatic(path: request.path)
        }
        guard st.isProxyHealthy else {
            if Self.bundledFusionPath() != nil {
                return serveStatic(path: request.path)
            }
            return Self.textResponse("asset unavailable while proxy healing: \(request.path)", code: 503)
        }
        let proxied = proxyToDevServer(path: "\(request.path)\(query)", request: request, devProxyPort: st.devProxyPort)
        if proxied.isSuccess {
            return proxied.response
        }
        return proxied.response
    }

    nonisolated private func serveStaticIfAvailableFallback(path: String) -> HttpResponse? {
        let fallbackAllowed = path == "/fusion-s4" ||
            path == "/fusion-s4/" ||
            path.hasPrefix("/fusion-s4/") ||
            path == "/substrate" ||
            path == "/substrate/" ||
            path.hasPrefix("/substrate") ||
            path == "/substrate-raw" ||
            path == "/substrate-raw/" ||
            path.hasPrefix("/substrate-raw")
        guard fallbackAllowed else {
            return nil
        }

        guard Self.bundledFusionPath() != nil else {
            return nil
        }
        return serveStatic(path: path)
    }

    nonisolated private static func proxyDownResponse(fallbackPath: String, devProxyPort: Int, boundPort: Int) -> HttpResponse {
        if fallbackPath.hasPrefix("/api/fusion/health") {
            return Self.jsonResponse([
                "status": "degraded",
                "detail": "dev proxy unavailable",
                "mode": "static-fallback",
                "dev_proxy_port": devProxyPort,
                "local_ui_port": boundPort,
            ])
        }
        let local = boundPort
        let upstream = devProxyPort
        let html = """
        <!DOCTYPE html><html lang="en"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>GaiaFusion — surface unavailable</title>
        <style>
          body { font-family: system-ui, sans-serif; margin: 0; padding: 2rem; background: #0b0b0c; color: #e8e8ea; line-height: 1.5; }
          h1 { font-size: 1.25rem; font-weight: 600; }
          code { background: #1a1a1d; padding: 0.15em 0.4em; border-radius: 4px; }
          .box { max-width: 40rem; margin: 0 auto; }
          button { margin-top: 1rem; padding: 0.5rem 1rem; cursor: pointer; border-radius: 6px; border: 1px solid #444; background: #1e1e22; color: inherit; }
          ul { padding-left: 1.2rem; }
        </style></head><body><div class="box">
        <h1>Fusion UI upstream unavailable</h1>
        <p>GaiaFusion could not load the Next.js dev surface from <code>http://127.0.0.1:\(upstream)</code>, and no bundled <code>fusion-web</code> assets were found.</p>
        <p><strong>Reserved for this app:</strong> WebView origin <code>http://127.0.0.1:\(local)</code> — run Next on a <em>different</em> port, e.g.:</p>
        <ul>
          <li><code>cd services/gaiaos_ui_web &amp;&amp; FUSION_UI_PORT=3000 npm run dev:fusion</code></li>
          <li>Or set <code>FUSION_UI_PROXY_PORT=3000</code> if your dev server uses another port.</li>
        </ul>
        <p>Self-heal will retry the dev upstream in the background. You can also turn off <strong>Dev mode</strong> in Config and rely on static <code>fusion-web</code> in the app bundle.</p>
        <button type="button" onclick="location.reload()">Retry</button>
        </div></body></html>
        """
        guard let data = html.data(using: .utf8) else {
            return Self.textResponse("dev proxy unavailable, self-healing in progress", code: 503)
        }
        return .raw(503, "Service Unavailable", ["Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"]) { writer in
            try writer.write(data)
        }
    }

    @MainActor
    private func markProxyRecovered() {
        proxyFailureCount = 0
        isProxyHealthy = true
        upstreamRecoveryActive = false
        recoveryTask?.cancel()
        recoveryTask = nil
        print("GaiaFusion dev proxy recovery complete. Reconnected to http://127.0.0.1:\(devProxyPort)")
        syncHTTPServingState()
    }

    @MainActor
    private func markProxyFailure() {
        proxyFailureCount += 1
        let previouslyHealthy = isProxyHealthy
        isProxyHealthy = proxyFailureCount < proxyFailureThreshold ? true : false
        if previouslyHealthy && !isProxyHealthy {
            print("GaiaFusion dev proxy degraded. Entering local fallback + self-heal loop.")
        }
        print("GaiaFusion dev proxy failure count: \(proxyFailureCount)")
        syncHTTPServingState()
    }

    /// Runs after the first failed dev proxy attempt: re-scan candidate ports (unless `FUSION_UI_PROXY_PORT` is set) and probe `fusion-s4` until the upstream returns.
    @MainActor
    private func startProxyRecovery() {
        guard isDevMode else {
            return
        }
        guard proxyFailureCount >= 1 else {
            return
        }
        guard recoveryTask == nil else {
            return
        }

        upstreamRecoveryActive = true
        let timer = DispatchSource.makeTimerSource(queue: recoveryQueue)
        timer.schedule(deadline: .now() + 0.35, repeating: Double(proxyRecoveryTick) / 1_000_000_000.0)
        timer.setEventHandler { [weak self] in
            guard let self else {
                timer.cancel()
                return
            }
            Task { @MainActor in
                self.reprobeDevProxyPortIfNeeded()
                let healthy = await self.checkDevProxyHealth()
                if healthy {
                    self.markProxyRecovered()
                }
            }
        }
        timer.resume()
        recoveryTask = timer
        print("GaiaFusion self-heal: upstream recovery timer started (failures=\(proxyFailureCount))")
    }

    /// When not pinned by `FUSION_UI_PROXY_PORT`, rediscover where `next dev` is listening (e.g. user started on 3000 after launch).
    @MainActor
    private func reprobeDevProxyPortIfNeeded() {
        guard ProcessInfo.processInfo.environment["FUSION_UI_PROXY_PORT"] == nil else {
            return
        }
        let local = Int(boundPort)
        let candidate = Self.detectDevProxyPort(excludingLocalPort: local)
        if candidate != devProxyPort {
            devProxyPort = candidate
            print("GaiaFusion self-heal: dev proxy port → \(devProxyPort)")
        }
        syncHTTPServingState()
    }

    private func checkDevProxyHealth() async -> Bool {
        // Next.js does not serve GaiaFusion’s /api/fusion/health — probe the real fusion route instead.
        guard let url = URL(string: "http://127.0.0.1:\(devProxyPort)/fusion-s4") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let code = (response as? HTTPURLResponse)?.statusCode {
                return (200 ... 399).contains(code)
            }
            return false
        } catch {
            return false
        }
    }

    nonisolated private func serveStatic(path: String) -> HttpResponse {
        let fusedPayloadPath = Self.bundledFusionPath()
        guard let bundlePath = fusedPayloadPath else {
            return Self.textResponse("fusion web assets not found", code: 404)
        }
        // Bundled tree uses a single `index.html` for /fusion-s4 and `substrate.html` for /substrate (SwiftPM forbids duplicate `index.html` paths under Resources).
        let requestPath: String = {
            if path == "/fusion-s4" || path == "/fusion-s4/" {
                return "index.html"
            }
            if path == "/substrate" || path == "/substrate/" {
                return "substrate.html"
            }
            if path == "/substrate-raw" || path == "/substrate-raw/" || path.hasPrefix("/substrate-raw/") {
                return "substrate-raw.html"
            }
            return path.replacingOccurrences(of: "/fusion-s4", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }()
        let candidate = bundlePath.appendingPathComponent(requestPath).standardizedFileURL
        var fileUrl: URL
        if requestPath.isEmpty || requestPath.hasSuffix("/") {
            fileUrl = candidate.appendingPathComponent("index.html")
        } else if FileManager.default.fileExists(atPath: candidate.path) {
            fileUrl = candidate
        } else {
            fileUrl = bundlePath.appendingPathComponent("index.html")
        }

        guard FileManager.default.fileExists(atPath: fileUrl.path),
              let bytes = try? Data(contentsOf: fileUrl)
        else {
            return Self.textResponse("fusion web asset missing", code: 404)
        }

        let ext = fileUrl.pathExtension.lowercased()
        let contentType = switch ext {
            case "html": "text/html; charset=utf-8"
            case "css": "text/css; charset=utf-8"
            case "js", "mjs": "application/javascript; charset=utf-8"
            case "json": "application/json; charset=utf-8"
            case "svg": "image/svg+xml"
            case "png": "image/png"
            case "jpg", "jpeg": "image/jpeg"
            case "woff2": "font/woff2"
            case "woff": "font/woff"
            default: "application/octet-stream"
        }

        return .raw(200, "OK", ["Content-Type": contentType]) { writer in
            try writer.write(bytes)
        }
    }

    nonisolated private static func bundledFusionPath() -> URL? {
        FusionEmbeddedAssetGate.resolvedFusionWebRootForServing()
    }

    nonisolated private static func jsonResponse(_ value: Any) -> HttpResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return Self.textResponse("json encode failed", code: 500)
        }
        return .raw(200, "OK", ["Content-Type": "application/json"] ) { writer in
            try writer.write(data)
        }
    }

    nonisolated private func serveSubstrateViewport(request: HttpRequest, fallbackPath: String) -> HttpResponse {
        guard let query = queryString(from: request) else {
            return serveFusionSurface(request: request, fallbackPath: fallbackPath)
        }
        return serveFusionSurface(request: request, fallbackPath: "\(fallbackPath)\(query)")
    }

    nonisolated private func queryString(from request: HttpRequest) -> String? {
        if request.queryParams.isEmpty {
            return nil
        }
        let query = request.queryParams
            .map { "\( $0.0 )=\($0.1)"}
            .joined(separator: "&")
        return "?\(query)"
    }

    nonisolated private static func textResponse(_ value: String, code: Int) -> HttpResponse {
        guard let data = value.data(using: .utf8) else {
            return .raw(500, "OK", ["Content-Type": "text/plain"], { _ in })
        }
        return .raw(code, "OK", ["Content-Type": "text/plain"], { writer in
            try writer.write(data)
        })
    }
}

@MainActor
private final class BridgeStatus {
    var webviewLoaded = false
}
