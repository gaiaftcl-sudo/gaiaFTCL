import XCTest
@testable import GaiaFusion

@MainActor
final class LocalServerAPITests: XCTestCase {
    private let testPort = 8945
    private var server: LocalServer!
    private var meshManager: MeshStateManager!
    private var testSession: URLSession!
    private var previousPort: Int?
    private var previousDevMode: Bool?

    override func setUp() async throws {
        try await super.setUp()
        meshManager = MeshStateManager()
        server = LocalServer(meshManager: meshManager)
        if UserDefaults.standard.object(forKey: "fusion_ui_port") != nil {
            previousPort = UserDefaults.standard.integer(forKey: "fusion_ui_port")
        }
        previousDevMode = UserDefaults.standard.object(forKey: "fusion_dev_mode") as? Bool
        UserDefaults.standard.setValue(testPort, forKey: "fusion_ui_port")
        UserDefaults.standard.setValue(false, forKey: "fusion_dev_mode")
        testSession = URLSession(configuration: .ephemeral)
        server.openUSDPlaybackProvider = {
            [
                "schema": "gaiaftcl_openusd_playback_v1",
                "plant_kind": "tokamak",
                "engaged": false,
                "frames_presented": 3,
                "fps": 30.0,
                "stage_loaded": true,
            ]
        }
        server.start()
        let ready = try waitUntilServerResponds(port: testPort)
        XCTAssertTrue(ready, "GaiaFusion local server did not start on test port \(testPort)")
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        meshManager = nil
        if let previousPort {
            UserDefaults.standard.setValue(previousPort, forKey: "fusion_ui_port")
        } else {
            UserDefaults.standard.removeObject(forKey: "fusion_ui_port")
        }
        if let previousDevMode {
            UserDefaults.standard.setValue(previousDevMode, forKey: "fusion_dev_mode")
        } else {
            UserDefaults.standard.removeObject(forKey: "fusion_dev_mode")
        }
        try await super.tearDown()
    }

    func testHealthEndpointReturnsOperationalPayload() async throws {
        let payload = try await readJSON(path: "/api/fusion/health")
        XCTAssertEqual(payload["status"] as? String, "ok")
        XCTAssertEqual(payload["v_qbit_projection"] as? String, "local_mesh_ratio")
        XCTAssertEqual(payload["mesh_nodes_total"] as? Int, MeshStateManager.MeshConstants.meshNodeCount)
        XCTAssertNotNil(payload["v_qbit_note"] as? String)
        XCTAssertEqual(payload["mode"] as? String, "static")
        XCTAssertEqual(payload["pid"] as? Int, Int(ProcessInfo.processInfo.processIdentifier))
        XCTAssertEqual(payload["local_ui_port"] as? Int, testPort)
        let selfHeal = payload["self_heal"] as? [String: Any]
        XCTAssertNotNil(selfHeal)
        XCTAssertEqual(selfHeal?["recovery_active"] as? Bool, false)
        XCTAssertEqual(selfHeal?["reprobe_upstream_allowed"] as? Bool, true)
        let kb = payload["klein_bottle"] as? [String: Any]
        XCTAssertNotNil(kb)
        XCTAssertNotNil(payload["klein_bottle_closed"] as? Bool)
        XCTAssertNotNil(kb?["closed"] as? Bool)
        let wasm = payload["wasm_surface"] as? [String: Any]
        XCTAssertNotNil(wasm)
        XCTAssertEqual(wasm?["monitoring"] as? Bool, false)
        XCTAssertNotNil(payload["wasm_surface_closed"] as? Bool)
        let cellStack = payload["cell_stack"] as? [String: Any]
        XCTAssertNotNil(cellStack)
        XCTAssertEqual(cellStack?["fusion_surface"] as? String, "native_swift")
        XCTAssertEqual(cellStack?["cell_substrate"] as? String, "docker_compose_bundled_full_cell")
        XCTAssertEqual(cellStack?["bundled_cell_compose_present"] as? Bool, true)
        let wasmRt = payload["wasm_runtime"] as? [String: Any]
        XCTAssertNotNil(wasmRt)
        XCTAssertEqual(wasmRt?["schema"] as? String, "gaiaftcl_wasm_runtime_v1")
        XCTAssertNotNil(payload["wasm_runtime_closed"] as? Bool)
        let usdPx = payload["usd_px"] as? [String: Any]
        XCTAssertNotNil(usdPx)
        XCTAssertGreaterThan(usdPx?["pxr_version_int"] as? Int ?? 0, 0)
        XCTAssertEqual(usdPx?["in_memory_stage"] as? Bool, true)
        XCTAssertEqual(usdPx?["plant_control_viewport_prim"] as? Bool, true)
        let openusd = payload["openusd_playback"] as? [String: Any]
        XCTAssertEqual(openusd?["schema"] as? String, "gaiaftcl_openusd_playback_v1")
        XCTAssertEqual(openusd?["frames_presented"] as? Int, 3)
    }

    func testBridgeStatusEndpointReportsBooleanShape() async throws {
        let payload = try await readJSON(path: "/api/fusion/bridge-status")
        XCTAssertEqual(payload["connected"] as? Bool, true)
        XCTAssertEqual(payload["webview_loaded"] as? Bool, false)
        let openusd = payload["openusd_playback"] as? [String: Any]
        XCTAssertEqual(openusd?["frames_presented"] as? Int, 3)
    }

    func testOpenUsdPlaybackEndpointReturnsSchema() async throws {
        let payload = try await readJSON(path: "/api/fusion/openusd-playback")
        XCTAssertEqual(payload["schema"] as? String, "gaiaftcl_openusd_playback_v1")
        XCTAssertEqual(payload["frames_presented"] as? Int, 3)
    }

    /// Full GaiaFusion.app links FusionBridge to LocalServer; unit test server alone expects REFUSED until bridge is attached.
    func testSelfProbeEndpointReturnsSchemaAndBridgeGate() async throws {
        let payload = try await readJSON(path: "/api/fusion/self-probe")
        XCTAssertEqual(payload["schema"] as? String, "gaiaftcl_fusion_self_probe_v1")
        XCTAssertEqual(payload["terminal"] as? String, "REFUSED")
        XCTAssertEqual(payload["reason"] as? String, "fusion_bridge_nil")
        XCTAssertEqual(payload["local_ui_port"] as? Int, testPort)
        let usdPx = payload["usd_px"] as? [String: Any]
        XCTAssertNotNil(usdPx)
        XCTAssertGreaterThan(usdPx?["pxr_version_int"] as? Int ?? 0, 0)
        XCTAssertNotNil(usdPx?["in_memory_stage"] as? Bool)
        XCTAssertEqual(usdPx?["plant_control_viewport_prim"] as? Bool, true)
    }

    func testCellsEndpointReturnsAllConfiguredNodes() async throws {
        let data = try await request(path: "/api/fusion/cells")
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, MeshStateManager.MeshConstants.meshNodeCount)
    }

    func testPlantKindsEndpointReturnsCanonicalKinds() async throws {
        let payload = try await readJSON(path: "/api/fusion/plant-kinds")
        let kinds = payload["kinds"] as? [String]
        XCTAssertNotNil(kinds)
        XCTAssertFalse((kinds ?? []).isEmpty)
        XCTAssertEqual(kinds?.count, 9)
        XCTAssertEqual(payload["count"] as? Int, 9)
        XCTAssertTrue((kinds ?? []).contains("tokamak"))
        XCTAssertTrue((kinds ?? []).contains("frc"))
        XCTAssertTrue((kinds ?? []).contains("spherical_tokamak"))
        XCTAssertTrue((kinds ?? []).contains("z_pinch"))
        XCTAssertTrue((kinds ?? []).contains("mif"))
        let aliases = payload["aliases"] as? [String: String]
        XCTAssertEqual(aliases?["icf"], "inertial")
        XCTAssertEqual(aliases?["pjmif"], "mif")
    }

    func testSwapEndpointRejectsWithoutQuorum() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/fusion/swap"))
        request.httpMethod = "POST"
        request.httpBody = """
        {"cell_id":"gaiaftcl-hcloud-hel1-01","input_plant_type":"tokamak","output_plant_type":"stellarator"}
        """.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await testSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Non-HTTP response for /api/fusion/swap")
            return
        }
        XCTAssertEqual(http.statusCode, 200)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(payload?["ok"] as? Bool, false)
        XCTAssertEqual(payload?["message"] as? String, "quorum_violation")
        XCTAssertEqual(payload?["cell_identity_hash"] as? String, "unverified")
    }

    func testSwapRejectsUnsupportedPlantKind() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/fusion/swap"))
        request.httpMethod = "POST"
        request.httpBody = """
        {"cell_id":"gaiaftcl-hcloud-hel1-01","input_plant_type":"hybrid","output_plant_type":"tokamak"}
        """.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await testSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Non-HTTP response for /api/fusion/swap")
            return
        }
        XCTAssertEqual(http.statusCode, 200)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(payload?["ok"] as? Bool, false)
        XCTAssertEqual(payload?["error"] as? String, "unsupported_plant_kind")
    }

    func testSwapRejectsUnknownPlantKind() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/fusion/swap"))
        request.httpMethod = "POST"
        request.httpBody = """
        {"cell_id":"gaiaftcl-hcloud-hel1-01","input_plant_type":"unknown","output_plant_type":"tokamak"}
        """.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await testSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Non-HTTP response for /api/fusion/swap")
            return
        }
        XCTAssertEqual(http.statusCode, 200)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(payload?["ok"] as? Bool, false)
        XCTAssertEqual(payload?["error"] as? String, "unsupported_plant_kind")
    }

    func testGateLoadViewportPlantWithoutHookReturnsNil() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/fusion/gate/load-viewport-plant"))
        request.httpMethod = "POST"
        request.httpBody = "{\"plant_kind\":\"stellarator\"}".data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await testSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Non-HTTP response for /api/fusion/gate/load-viewport-plant")
            return
        }
        XCTAssertEqual(http.statusCode, 200)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(payload?["ok"] as? Bool, false)
        XCTAssertEqual(payload?["error"] as? String, "load_viewport_plant_hook_nil")
    }

    func testS4ProjectionEndpointReturnsProjectionShape() async throws {
        let payload = try await readJSON(path: "/api/fusion/s4-projection")
        let projection = payload["projection_s4"] as? [String: Any]
        XCTAssertNotNil(projection)
        XCTAssertNotNil(payload["flow_catalog_s4"] as? [String: Any])
        XCTAssertNotNil(payload["schema"] as? String)
        let production = payload["production_systems_ui"] as? [String: Any]
        XCTAssertNotNil(production)
    }

    func testFleetDigestEndpointReturnsTopologyShape() async throws {
        let payload = try await readJSON(path: "/api/fusion/fleet-digest")
        XCTAssertEqual(payload["schema"] as? String, "gaiaftcl_fleet_digest_v1")
        let mesh = payload["mesh"] as? [String: Any]
        XCTAssertEqual(mesh?["total"] as? Int, MeshStateManager.MeshConstants.meshNodeCount)
        XCTAssertTrue((payload["cells"] as? [[String: Any]]) != nil)
    }

    func testSovereignMeshEndpointReturnsExpectedShape() async throws {
        let payload = try await readJSON(path: "/api/sovereign-mesh")
        XCTAssertEqual(payload["schema"] as? String, "gaiaftcl_fusion_sovereign_mesh_v1")
        XCTAssertNotNil(payload["panels"] as? [String: Any])
        XCTAssertNotNil(payload["nats_connected"] as? Bool)
        XCTAssertEqual(payload["v_qbit_projection"] as? String, "local_mesh_ratio")
        XCTAssertEqual(payload["mesh_nodes_total"] as? Int, MeshStateManager.MeshConstants.meshNodeCount)
        XCTAssertNotNil(payload["wasm_runtime_closed"] as? Bool)
    }

    /// Poll without a non-`Sendable` closure (Swift 6 / `@MainActor` tests).
    private func waitUntilServerResponds(port: Int) throws -> Bool {
        let timeoutAt = Date().addingTimeInterval(5)
        while Date() < timeoutAt {
            guard let url = URL(string: "http://127.0.0.1:\(port)/api/fusion/health") else {
                return false
            }
            if (try? Data(contentsOf: url)) != nil {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(testPort)")!
    }

    private func request(path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await testSession.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            XCTFail("Non-200 response for \(path)")
            return Data()
        }
        return data
    }

    private func readJSON(path: String) async throws -> [String: Any] {
        let data = try await request(path: path)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(payload)
        return payload ?? [:]
    }
}
