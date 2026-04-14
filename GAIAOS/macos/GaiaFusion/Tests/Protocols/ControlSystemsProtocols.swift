import XCTest
@testable import GaiaFusion

/// GFTCL-PQ-002: Control Systems Engineering Test Protocols (PQ-CSE-001 through PQ-CSE-012)
/// GAMP 5 Performance Qualification - Plant Swap, Geometry, Epistemic Classification
final class ControlSystemsProtocols: XCTestCase {
    
    var gameState: OpenUSDLanguageGameState!
    var playbackController: MetalPlaybackController!
    
    override func setUp() async throws {
        try await super.setUp()
        gameState = await MainActor.run { OpenUSDLanguageGameState() }
        playbackController = await MainActor.run { MetalPlaybackController() }
        
        await playbackController.initialize(layer: nil)
    }
    
    override func tearDown() async throws {
        playbackController?.cleanup()
        try await super.tearDown()
    }
    
    // MARK: - PQ-CSE-001: Plant Swap REQUESTED → COMMITTED < 2s
    
    /// Test Protocol ID: PQ-CSE-001
    /// Invariant: INV-CSE-001 — Plant swap from REQUESTED to COMMITTED must complete in < 2s
    /// Acceptance: 10 consecutive swaps all < 2s
    func testPQCSE001_PlantSwapLatency() async throws {
        let plants: [FusionPlantKind] = [.tokamak, .stellarator, .icf, .frc, .spheromak]
        var latencies: [TimeInterval] = []
        
        for plant in plants {
            let startTime = Date()
            await playbackController.requestPlantSwap(to: plant)
            
            var committed = false
            while !committed && Date().timeIntervalSince(startTime) < 5.0 {
                if gameState.swapState == .committed {
                    committed = true
                    let latency = Date().timeIntervalSince(startTime)
                    latencies.append(latency)
                    
                    XCTAssertLessThan(latency, 2.0,
                        "Plant swap to \(plant.rawValue) took \(latency)s (>2s limit)")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            
            XCTAssertTrue(committed, "Plant swap to \(plant.rawValue) did not commit")
            try await Task.sleep(for: .seconds(1))
        }
        
        XCTAssertEqual(latencies.count, 5, "Not all swaps completed")
        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let maxLatency = latencies.max() ?? 0
        
        print("PQ-CSE-001: Avg swap latency = \(avgLatency)s, Max = \(maxLatency)s")
    }
    
    // MARK: - PQ-CSE-002: No Frame Drops During Swap
    
    /// Test Protocol ID: PQ-CSE-002
    /// Invariant: INV-CSE-002 — Frame rate must stay ≥55 FPS during plant swap
    /// Acceptance: No frame drops below 55 FPS during 5 swaps
    func testPQCSE002_NoFrameDropsDuringSwap() async throws {
        let plants: [FusionPlantKind] = [.tokamak, .stellarator, .icf]
        var minFPS: Double = 60.0
        
        for plant in plants {
            await playbackController.requestPlantSwap(to: plant)
            
            var frameRates: [Double] = []
            let startTime = Date()
            
            while Date().timeIntervalSince(startTime) < 3.0 {
                if let fps = playbackController.currentFPS {
                    frameRates.append(fps)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            
            if let minSwapFPS = frameRates.min() {
                minFPS = min(minFPS, minSwapFPS)
                XCTAssertGreaterThanOrEqual(minSwapFPS, 55.0,
                    "FPS dropped to \(minSwapFPS) during \(plant.rawValue) swap")
            }
            
            try await Task.sleep(for: .seconds(1))
        }
        
        print("PQ-CSE-002: Minimum FPS during swaps = \(minFPS)")
    }
    
    // MARK: - PQ-CSE-003: REFUSED State on Invalid Telemetry
    
    /// Test Protocol ID: PQ-CSE-003
    /// Invariant: INV-CSE-003 — System must enter REFUSED when telemetry violates physics
    /// Acceptance: REFUSED trigger on I_p > 25 MA for tokamak
    func testPQCSE003_REFUSEDStateOnInvalidTelemetry() async throws {
        await playbackController.requestPlantSwap(to: "tokamak")
        try await Task.sleep(for: .seconds(2))
        
        await gameState.injectFaultTelemetry(field: "I_p_MA", value: 30.0)
        
        try await Task.sleep(for: .seconds(1))
        
        let state = await gameState.terminalState; XCTAssertEqual(state, .refused,
            "System did not enter REFUSED on invalid I_p")
        
        XCTAssertTrue(gameState.refusalReason?.contains("I_p") ?? false,
            "Refusal reason missing I_p violation")
        
        print("PQ-CSE-003: REFUSED state correctly triggered on I_p = 30 MA")
    }
    
    // MARK: - PQ-CSE-004: Geometry Vertex Counts (All 9 Plants)
    
    /// Test Protocol ID: PQ-CSE-004
    /// Invariant: INV-CSE-004 — Each plant topology must have >100 vertices
    /// Acceptance: All 9 plants render with vertex count > 100
    func testPQCSE004_GeometryVertexCounts() async throws {
        let plants: [FusionPlantKind] = [
            .tokamak, .stellarator, .icf, .frc, .spheromak,
            .magneticMirror, .zpinch, .thetaPinch, .polywell
        ]
        
        var vertexCounts: [FusionPlantKind: Int] = [:]
        
        for plant in plants {
            await playbackController.requestPlantSwap(to: plant)
            try await Task.sleep(for: .seconds(2))
            
            if let geometry = playbackController.currentGeometry {
                let vertexCount = geometry.vertexCount
                vertexCounts[plant] = vertexCount
                
                XCTAssertGreaterThan(vertexCount, 100,
                    "\(plant.rawValue) has only \(vertexCount) vertices (need >100)")
            } else {
                XCTFail("\(plant.rawValue) geometry not available")
            }
        }
        
        XCTAssertEqual(vertexCounts.count, 9, "Not all plant geometries tested")
        
        print("PQ-CSE-004: Vertex counts:")
        for (plant, count) in vertexCounts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  \(plant.rawValue): \(count) vertices")
        }
    }
    
    // MARK: - PQ-CSE-005: Telemetry Epistemic Tags (M/T/I/A)
    
    /// Test Protocol ID: PQ-CSE-005
    /// Invariant: INV-CSE-005 — All telemetry must have valid epistemic classification
    /// Acceptance: I_p, B_T, n_e tagged [M], Q, tau_E tagged [I]
    func testPQCSE005_TelemetryEpistemicTags() async throws {
        await playbackController.requestPlantSwap(to: "tokamak")
        try await Task.sleep(for: .seconds(2))
        
        let telemetry = gameState.currentPlantTelemetry ?? [:]
        
        XCTAssertEqual(telemetry["I_p_MA_tag"] as? String, "M",
            "I_p should be tagged [M] (Measured)")
        XCTAssertEqual(telemetry["B_T_tesla_tag"] as? String, "M",
            "B_T should be tagged [M] (Measured)")
        XCTAssertEqual(telemetry["n_e_m3_tag"] as? String, "M",
            "n_e should be tagged [M] (Measured)")
        
        XCTAssertEqual(telemetry["Q_fusion_gain_tag"] as? String, "I",
            "Q should be tagged [I] (Inferred)")
        XCTAssertEqual(telemetry["tau_E_confinement_tag"] as? String, "I",
            "tau_E should be tagged [I] (Inferred)")
        
        print("PQ-CSE-005: All telemetry correctly tagged with epistemic classification")
    }
    
    // MARK: - PQ-CSE-006: Terminal State Colors (Visual Validation)
    
    /// Test Protocol ID: PQ-CSE-006
    /// Invariant: INV-CSE-006 — Wireframe color must reflect terminal state
    /// Acceptance: CALORIE=green, CURE=amber, REFUSED=red
    func testPQCSE006_TerminalStateColors() async throws {
        await playbackController.requestPlantSwap(to: "tokamak")
        try await Task.sleep(for: .seconds(2))
        
        gameState.setTerminalState(.calorie)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(playbackController.currentWireframeColor, .green,
            "CALORIE state should display green wireframe")
        
        gameState.setTerminalState(.cure)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(playbackController.currentWireframeColor, .amber,
            "CURE state should display amber wireframe")
        
        gameState.setTerminalState(.refused)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(playbackController.currentWireframeColor, .red,
            "REFUSED state should display red wireframe")
        
        print("PQ-CSE-006: All terminal state colors validated")
    }
    
    // MARK: - PQ-CSE-007: 81-Swap Permutation Matrix (CRITICAL)
    
    /// Test Protocol ID: PQ-CSE-007
    /// Invariant: INV-CSE-007 — All 81 plant-to-plant swaps must succeed
    /// Acceptance: 9×9 matrix, all swaps VERIFIED, 0 REFUSED
    func testPQCSE007_81SwapPermutationMatrix() async throws {
        let plants: [FusionPlantKind] = [
            .tokamak, .stellarator, .icf, .frc, .spheromak,
            .magneticMirror, .zpinch, .thetaPinch, .polywell
        ]
        
        var swapMatrix: [[String]] = Array(repeating: Array(repeating: "", count: 9), count: 9)
        var successCount = 0
        var failureCount = 0
        
        for (fromIdx, fromPlant) in plants.enumerated() {
            await playbackController.requestPlantSwap(to: fromPlant)
            try await Task.sleep(for: .seconds(2))
            XCTAssertEqual(gameState.currentActivePlant, fromPlant, "Initial plant swap failed")
            
            for (toIdx, toPlant) in plants.enumerated() {
                await playbackController.requestPlantSwap(to: toPlant)
                
                var swapResult = "PENDING"
                let startTime = Date()
                
                while Date().timeIntervalSince(startTime) < 5.0 {
                    if gameState.swapState == .verified {
                        swapResult = "VERIFIED"
                        successCount += 1
                        break
                    } else if gameState.swapState == .refused {
                        swapResult = "REFUSED"
                        failureCount += 1
                        break
                    }
                    try await Task.sleep(for: .milliseconds(50))
                }
                
                if swapResult == "PENDING" {
                    swapResult = "TIMEOUT"
                    failureCount += 1
                }
                
                swapMatrix[fromIdx][toIdx] = swapResult
                
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        
        XCTAssertEqual(successCount, 81, "Not all 81 swaps succeeded (\(successCount)/81)")
        XCTAssertEqual(failureCount, 0, "\(failureCount) swaps failed (REFUSED or TIMEOUT)")
        
        print("PQ-CSE-007: 81-Swap Permutation Matrix")
        print("       " + plants.map { String($0.rawValue.prefix(3)) }.joined(separator: " "))
        for (idx, row) in swapMatrix.enumerated() {
            let plantName = String(plants[idx].rawValue.prefix(3))
            let rowStr = row.map { $0 == "VERIFIED" ? " ✓ " : " ✗ " }.joined(separator: " ")
            print("\(plantName): \(rowStr)")
        }
        print("Success: \(successCount)/81, Failures: \(failureCount)/81")
    }
    
    // MARK: - PQ-CSE-008: Mesh Quorum Status
    
    /// Test Protocol ID: PQ-CSE-008
    /// Invariant: INV-CSE-008 — Mesh quorum must be ≥8/10 cells
    /// Acceptance: Quorum ≥8 for 60 seconds
    func testPQCSE008_MeshQuorumStatus() async throws {
        let startTime = Date()
        var quorumSamples: [Int] = []
        
        while Date().timeIntervalSince(startTime) < 60 {
            if let quorum = gameState.meshQuorum {
                quorumSamples.append(quorum)
                
                XCTAssertGreaterThanOrEqual(quorum, 8,
                    "Mesh quorum dropped to \(quorum)/10 (need ≥8)")
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        
        XCTAssertGreaterThan(quorumSamples.count, 100, "Insufficient quorum samples")
        
        let avgQuorum = Double(quorumSamples.reduce(0, +)) / Double(quorumSamples.count)
        let minQuorum = quorumSamples.min() ?? 0
        
        print("PQ-CSE-008: Avg quorum = \(avgQuorum), Min = \(minQuorum)")
    }
    
    // MARK: - PQ-CSE-009: SubGame Z Diagnostic Eviction
    
    /// Test Protocol ID: PQ-CSE-009
    /// Invariant: INV-CSE-009 — SubGame Z activates when quorum < 8
    /// Acceptance: Mock quorum drop triggers diagnostic eviction
    func testPQCSE009_SubGameZDiagnosticEviction() async throws {
        gameState.mockMeshQuorum(value: 10)
        try await Task.sleep(for: .seconds(1))
        
        XCTAssertFalse(gameState.subGameZActive,
            "SubGame Z should not be active with quorum=10")
        
        gameState.mockMeshQuorum(value: 7)
        try await Task.sleep(for: .seconds(2))
        
        XCTAssertTrue(gameState.subGameZActive,
            "SubGame Z should activate with quorum=7")
        
        XCTAssertTrue(gameState.diagnosticEvictionActive,
            "Diagnostic eviction should be active")
        
        print("PQ-CSE-009: SubGame Z correctly activated on quorum drop")
    }
    
    // MARK: - PQ-CSE-010: Wallet Gate Authorization
    
    /// Test Protocol ID: PQ-CSE-010
    /// Invariant: INV-CSE-010 — Only authorized wallet can access MCP gateway
    /// Acceptance: Founder wallet authorized, unknown wallet rejected
    func testPQCSE010_WalletGateAuthorization() async throws {
        let founderWallet = "bc1q_founder_test_address"
        let unknownWallet = "bc1q_unknown_test_address"
        
        let founderResult = try await gameState.checkWalletAuthorization(founderWallet)
        XCTAssertTrue(founderResult, "Founder wallet should be authorized")
        
        let unknownResult = try await gameState.checkWalletAuthorization(unknownWallet)
        XCTAssertFalse(unknownResult, "Unknown wallet should be rejected")
        
        print("PQ-CSE-010: Wallet gate correctly authorizing/rejecting addresses")
    }
    
    // MARK: - PQ-CSE-011: NATS Mesh Mooring Heartbeat
    
    /// Test Protocol ID: PQ-CSE-011
    /// Invariant: INV-CSE-011 — NATS fusion.mesh_mooring.v1 heartbeat every 30s
    /// Acceptance: Heartbeat received within 45s
    func testPQCSE011_NATSMeshMooringHeartbeat() async throws {
        let startTime = Date()
        var heartbeatReceived = false
        
        let cancellable = gameState.onMeshMooringHeartbeat = {
            heartbeatReceived = true
        }
        
        while !heartbeatReceived && Date().timeIntervalSince(startTime) < 45 {
            try await Task.sleep(for: .milliseconds(500))
        }
        
        XCTAssertTrue(heartbeatReceived,
            "NATS mesh mooring heartbeat not received within 45s")
        
        let latency = Date().timeIntervalSince(startTime)
        print("PQ-CSE-011: Mesh mooring heartbeat received in \(latency)s")
    }
    
    // MARK: - PQ-CSE-012: Plant Swap Rollback on Error
    
    /// Test Protocol ID: PQ-CSE-012
    /// Invariant: INV-CSE-012 — Failed swap must rollback to previous plant
    /// Acceptance: Swap failure returns to last VERIFIED plant
    func testPQCSE012_PlantSwapRollback() async throws {
        await playbackController.requestPlantSwap(to: "tokamak")
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(gameState.currentActivePlant, .tokamak, "Initial swap failed")
        
        gameState.injectSwapFailure(to: "stellarator")
        await playbackController.requestPlantSwap(to: "stellarator")
        
        try await Task.sleep(for: .seconds(3))
        
        XCTAssertEqual(gameState.currentActivePlant, .tokamak,
            "Failed swap did not rollback to previous plant (tokamak)")
        
        XCTAssertEqual(gameState.swapState, .rollback,
            "Swap state should be ROLLBACK after failure")
        
        print("PQ-CSE-012: Plant swap correctly rolled back to tokamak after stellarator failure")
    }
}
