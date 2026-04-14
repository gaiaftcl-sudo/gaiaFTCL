import XCTest
@testable import GaiaFusion

/// GFTCL-PQ-002: Safety Team Test Protocols (PQ-SAF-001 through PQ-SAF-008)
/// GAMP 5 Performance Qualification - Safety Systems and NCR Triggers
final class SafetyTeamProtocols: XCTestCase {
    
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
    
    // MARK: - PQ-SAF-001: Emergency SCRAM on Physics Violation
    
    /// Test Protocol ID: PQ-SAF-001
    /// Invariant: INV-SAF-001 — System must SCRAM when I_p exceeds 25 MA
    /// Acceptance: REFUSED state + SCRAM trigger logged
    func testPQSAF001_EmergencySCRAMOnPhysicsViolation() async throws {
        await playbackController.requestPlantSwap(to: "tokamak")
        try await Task.sleep(for: .seconds(2))
        
        await gameState.injectFaultTelemetry(field: "I_p_MA", value: 26.0)
        
        try await Task.sleep(for: .seconds(1))
        
        let state = await gameState.terminalState; XCTAssertEqual(state, .refused,
            "System did not enter REFUSED on I_p violation")
        
        XCTAssertTrue(gameState.scramTriggered,
            "SCRAM not triggered on physics violation")
        
        let logged = await gameState.ncrLogged; XCTAssertTrue(logged,
            "NCR not logged for SCRAM event")
        
        print("PQ-SAF-001: Emergency SCRAM correctly triggered on I_p = 26 MA")
    }
    
    // MARK: - PQ-SAF-002: Mesh Quorum Loss → Diagnostic Eviction
    
    /// Test Protocol ID: PQ-SAF-002
    /// Invariant: INV-SAF-002 — Quorum < 8 must trigger SubGame Z
    /// Acceptance: SubGame Z active, all diagnostics evicted
    func testPQSAF002_MeshQuorumLossDiagnosticEviction() async throws {
        gameState.mockMeshQuorum(value: 10)
        try await Task.sleep(for: .seconds(1))
        
        XCTAssertFalse(gameState.subGameZActive,
            "SubGame Z should not be active with healthy quorum")
        
        gameState.mockMeshQuorum(value: 6)
        try await Task.sleep(for: .seconds(2))
        
        XCTAssertTrue(gameState.subGameZActive,
            "SubGame Z did not activate on quorum loss")
        
        XCTAssertTrue(gameState.diagnosticEvictionActive,
            "Diagnostic eviction not active")
        
        let logged = await gameState.ncrLogged; XCTAssertTrue(logged,
            "NCR not logged for quorum loss")
        
        print("PQ-SAF-002: SubGame Z correctly activated on quorum = 6")
    }
    
    // MARK: - PQ-SAF-003: REFUSED State Persistent Until Ack
    
    /// Test Protocol ID: PQ-SAF-003
    /// Invariant: INV-SAF-003 — REFUSED state must persist until operator ack
    /// Acceptance: Plant swap blocked until REFUSED acknowledged
    func testPQSAF003_REFUSEDStatePersistentUntilAck() async throws {
        await playbackController.requestPlantSwap(to: "tokamak")
        try await Task.sleep(for: .seconds(2))
        
        await gameState.injectFaultTelemetry(field: "I_p_MA", value: 30.0)
        try await Task.sleep(for: .seconds(1))
        
        let state = await gameState.terminalState; XCTAssertEqual(state, .refused,
            "System not in REFUSED state")
        
        await playbackController.requestPlantSwap(to: "stellarator")
        try await Task.sleep(for: .seconds(2))
        
        XCTAssertEqual(gameState.currentActivePlant, .tokamak,
            "Plant swap succeeded while REFUSED (should be blocked)")
        
        gameState.acknowledgeRefusal()
        try await Task.sleep(for: .seconds(1))
        
        await playbackController.requestPlantSwap(to: "stellarator")
        try await Task.sleep(for: .seconds(2))
        
        XCTAssertEqual(gameState.currentActivePlant, .stellarator,
            "Plant swap failed after REFUSED acknowledgment")
        
        print("PQ-SAF-003: REFUSED state correctly persisted until operator ack")
    }
    
    // MARK: - PQ-SAF-004: NCR Log Immutable (Audit Trail)
    
    /// Test Protocol ID: PQ-SAF-004
    /// Invariant: INV-SAF-004 — NCR log must be append-only, immutable
    /// Acceptance: NCR cannot be edited or deleted after creation
    func testPQSAF004_NCRLogImmutable() async throws {
        await gameState.injectFaultTelemetry(field: "I_p_MA", value: 30.0)
        try await Task.sleep(for: .seconds(1))
        
        guard let ncrID = gameState.lastNCRID else {
            XCTFail("No NCR created")
            return
        }
        
        let originalNCR = try gameState.getNCR(id: ncrID)
        
        let editResult = try? gameState.editNCR(id: ncrID, field: "reason", value: "modified")
        XCTAssertNil(editResult, "NCR edit succeeded (should be immutable)")
        
        let deleteResult = try? gameState.deleteNCR(id: ncrID)
        XCTAssertNil(deleteResult, "NCR delete succeeded (should be immutable)")
        
        let currentNCR = try gameState.getNCR(id: ncrID)
        XCTAssertEqual(originalNCR, currentNCR,
            "NCR was modified (should be immutable)")
        
        print("PQ-SAF-004: NCR log correctly immutable (append-only)")
    }
    
    // MARK: - PQ-SAF-005: Bitcoin τ Divergence > 10 Blocks → REFUSED
    
    /// Test Protocol ID: PQ-SAF-005
    /// Invariant: INV-SAF-005 — Mac cell τ divergence > 10 blocks triggers REFUSED
    /// Acceptance: REFUSED when |τ_mac - τ_mesh| > 10
    func testPQSAF005_BitcoinTauDivergenceREFUSED() async throws {
        gameState.mockBitcoinTau(mac: 1000, mesh: 1000)
        try await Task.sleep(for: .seconds(1))
        
        XCTAssertNotEqual(gameState.terminalState, .refused,
            "System REFUSED with synchronized τ")
        
        gameState.mockBitcoinTau(mac: 1000, mesh: 1012)
        try await Task.sleep(for: .seconds(2))
        
        let state = await gameState.terminalState; XCTAssertEqual(state, .refused,
            "System did not REFUSE with Δτ = 12 blocks")
        
        let logged = await gameState.ncrLogged; XCTAssertTrue(logged,
            "NCR not logged for τ divergence")
        
        XCTAssertTrue(gameState.refusalReason?.contains("tau") ?? false,
            "Refusal reason missing τ divergence")
        
        print("PQ-SAF-005: REFUSED correctly triggered on Δτ = 12 blocks")
    }
    
    // MARK: - PQ-SAF-006: Wallet Gate Unauthorized Access Blocked
    
    /// Test Protocol ID: PQ-SAF-006
    /// Invariant: INV-SAF-006 — Unauthorized wallet must be blocked at gateway
    /// Acceptance: 402 PAYMENT_REQUIRED for unauthorized wallet
    func testPQSAF006_WalletGateUnauthorizedAccessBlocked() async throws {
        let unauthorizedWallet = "bc1q_malicious_test_address"
        
        do {
            let _ = try await gameState.accessMCPGateway(wallet: unauthorizedWallet)
            XCTFail("Unauthorized wallet accessed gateway (should be blocked)")
        } catch let error as GatewayError {
            XCTAssertEqual(error.code, 402,
                "Expected 402 PAYMENT_REQUIRED, got \(error.code)")
            
            let logged = await gameState.ncrLogged; XCTAssertTrue(logged,
                "NCR not logged for unauthorized access attempt")
            
            print("PQ-SAF-006: Unauthorized wallet correctly blocked with 402")
        }
    }
    
    // MARK: - PQ-SAF-007: NATS Connection Loss → Degraded Mode
    
    /// Test Protocol ID: PQ-SAF-007
    /// Invariant: INV-SAF-007 — NATS disconnect must trigger degraded mode
    /// Acceptance: Degraded mode active, mesh telemetry unavailable
    func testPQSAF007_NATSConnectionLossDegradedMode() async throws {
        let natsService = NATSService.shared
        try await natsService.connect()
        
        XCTAssertFalse(gameState.degradedModeActive,
            "Degraded mode active with healthy NATS")
        
        natsService.simulateDisconnect()
        try await Task.sleep(for: .seconds(2))
        
        XCTAssertTrue(gameState.degradedModeActive,
            "Degraded mode not activated on NATS disconnect")
        
        XCTAssertFalse(gameState.meshTelemetryAvailable,
            "Mesh telemetry still available in degraded mode")
        
        let logged = await gameState.ncrLogged; XCTAssertTrue(logged,
            "NCR not logged for NATS disconnect")
        
        print("PQ-SAF-007: Degraded mode correctly activated on NATS disconnect")
    }
    
    // MARK: - PQ-SAF-008: Operator Override Requires 2FA
    
    /// Test Protocol ID: PQ-SAF-008
    /// Invariant: INV-SAF-008 — REFUSED override requires 2FA authentication
    /// Acceptance: Override fails without valid 2FA token
    func testPQSAF008_OperatorOverrideRequires2FA() async throws {
        await gameState.injectFaultTelemetry(field: "I_p_MA", value: 30.0)
        try await Task.sleep(for: .seconds(1))
        
        let state = await gameState.terminalState; XCTAssertEqual(state, .refused,
            "System not in REFUSED state")
        
        let overrideWithout2FA = try? gameState.overrideRefusal(token: nil)
        XCTAssertNil(overrideWithout2FA,
            "REFUSED override succeeded without 2FA (should fail)")
        
        let overrideWithInvalid2FA = try? gameState.overrideRefusal(token: "invalid_token")
        XCTAssertNil(overrideWithInvalid2FA,
            "REFUSED override succeeded with invalid 2FA (should fail)")
        
        let valid2FAToken = gameState.generate2FAToken()
        let overrideWithValid2FA = try? gameState.overrideRefusal(token: valid2FAToken)
        XCTAssertNotNil(overrideWithValid2FA,
            "REFUSED override failed with valid 2FA (should succeed)")
        
        let logged = await gameState.ncrLogged; XCTAssertTrue(logged,
            "NCR not logged for operator override")
        
        print("PQ-SAF-008: Operator override correctly requires 2FA")
    }
}
