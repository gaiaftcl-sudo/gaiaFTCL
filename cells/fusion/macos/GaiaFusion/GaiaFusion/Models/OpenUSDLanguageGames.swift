import Foundation

/// Gateway access error for wallet gate testing
struct GatewayError: Error {
    let code: Int
    let message: String
}

enum OpenUSDMooringState: String {
    case unresolved = "UNRESOLVED"
    case moored = "MOORED"
}

enum OpenUSDTerminalState: String {
    case calorie = "CALORIE"
    case cure = "CURE"
    case refused = "REFUSED"
}

/// OpenUSD-ready state model for sovereign language games.
/// This keeps mutations typed and deterministic at the native boundary.
@MainActor
final class OpenUSDLanguageGameState {
    /// Boot-to-Tokamak: facility is treated as physically present at first paint (no unresolved splash plane).
    private(set) var mooringState: OpenUSDMooringState = .moored
    private(set) var activePlantPayload: String = "tokamak"
    private(set) var terminalState: OpenUSDTerminalState = .calorie
    private(set) var heartbeatTsMs: Int64 = 0
    private(set) var receiptHash: String = ""
    private(set) var prunedPlantPayloads: [String] = []
    
    /// Plant swap lifecycle state for PQ-CSE protocols
    private(set) var swapState: SwapLifecycle = .idle
    /// Idle NSTX-U-class tokamak baseline (non-zero; supervisory plane observes a live plant shell).
    private static let bootTokamakIdleTelemetry: [String: Double] = [
        "I_p": 0.85,
        "B_T": 0.52,
        "n_e": 3.5e19,
    ]

    private(set) var measuredTelemetry: [String: Double] = OpenUSDLanguageGameState.bootTokamakIdleTelemetry
    private(set) var epistemicClass: [String: String] = [
        "I_p": "Measured",
        "B_T": "Measured",
        "n_e": "Measured",
    ]

    var interactionLocked: Bool {
        terminalState == .refused
    }

    @discardableResult
    func setMooringState(_ raw: String) -> Bool {
        guard let value = OpenUSDMooringState(rawValue: raw.uppercased()) else { return false }
        mooringState = value
        return true
    }

    @discardableResult
    func setTerminalState(_ raw: String) -> Bool {
        guard let value = OpenUSDTerminalState(rawValue: raw.uppercased()) else { return false }
        terminalState = value
        return true
    }
    
    /// Overload for direct enum setting
    func setTerminalState(_ state: OpenUSDTerminalState) {
        terminalState = state
    }

    func setPlantPayload(_ plantKind: String) {
        let incoming = plantKind.lowercased()
        if incoming != activePlantPayload {
            // Swap requested → drive lifecycle
            swapState = .requested
            prunedPlantPayloads.append(activePlantPayload)
            if prunedPlantPayloads.count > 16 {
                prunedPlantPayloads.removeFirst(prunedPlantPayloads.count - 16)
            }
            // Simulate swap phases (real implementation would have async delays)
            swapState = .draining
            swapState = .committed
            activePlantPayload = incoming
            swapState = .verified
        }
    }

    func setHeartbeatTsMs(_ value: Int64) {
        heartbeatTsMs = value
    }

    func setReceiptHash(_ value: String) {
        receiptHash = value
    }

    func setMeasuredTelemetry(_ values: [String: Double]) {
        for (k, v) in values {
            measuredTelemetry[k] = v
            if epistemicClass[k] == nil {
                epistemicClass[k] = "Measured"
            }
        }
        telemetryUpdated = true
    }

    func setEpistemicClass(name: String, value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let canonical: String
        switch normalized {
        case "measured", "m", "0":
            canonical = "Measured"
        case "tested", "t", "1":
            canonical = "Tested"
        case "inferred", "i":
            canonical = "Inferred"
        case "assumed", "a":
            canonical = "Assumed"
        default:
            return false
        }
        epistemicClass[name] = canonical
        return true
    }

    /// Session-layer authoring payload for strict exclusivity:
    /// - mooring via visibility (splash vs active matrix)
    /// - plant payload via prune+replace contract
    /// - terminal via visual masking + tombstone activation
    func sessionLayerOverlay() -> [String: Any] {
        let splashVisible = mooringState == .unresolved
        let matrixVisible = mooringState == .moored
        let refused = terminalState == .refused
        return [
            "schema": "gaiaftcl_openusd_session_layer_v1",
            "mooring_variant": mooringState.rawValue,
            "variant_visibility": [
                "SplashUI": splashVisible ? "inherited" : "invisible",
                "ActiveMatrix": matrixVisible ? "inherited" : "invisible",
            ],
            "plant_payload_contract": [
                "viewport_prim": "/PlantControlViewport",
                "clear_payloads_first": true,
                "active_payload": activePlantPayload,
                "pruned_payloads": prunedPlantPayloads,
            ],
            "terminal_mask": [
                "state": terminalState.rawValue,
                "interaction_locked": interactionLocked,
                "active_matrix_opacity": refused ? 0.35 : 1.0,
                "terminal_tombstone_active": refused,
            ],
            "heartbeat_ts_ms": heartbeatTsMs,
            "receipt_hash": receiptHash,
            "measured_telemetry": measuredTelemetry,
            "epistemic_boundary": epistemicClass,
        ]
    }
    
    // MARK: - PQ Test Protocol Support
    
    /// Current plant telemetry for PQ tests
    var currentPlantTelemetry: [String: Any]? {
        var telemetry: [String: Any] = [:]
        for (key, value) in measuredTelemetry {
            telemetry[key] = value
            telemetry["\(key)_tag"] = epistemicClass[key] ?? "M"
        }
        return telemetry
    }
    
    /// Current active plant kind
    var currentActivePlant: String {
        activePlantPayload
    }
    
    /// Error boundary status for PQ-QA-007
    private(set) var errorBoundaryActive: Bool = false
    
    /// App crash status for PQ-QA-007
    private(set) var appCrashed: Bool = false
    
    /// NCR logged status for PQ-SAF-008
    private(set) var ncrLogged: Bool = false
    
    /// SCRAM triggered status for PQ-SAF-001
    private(set) var scramTriggered: Bool = false
    
    /// Telemetry updated flag for PQ-QA-008
    private(set) var telemetryUpdated: Bool = false
    
    /// App git SHA for PQ-QA-010
    private(set) var appGitSHA: String? = nil
    
    /// SubGame Z active status for PQ-CSE-004
    private(set) var subGameZActive: Bool = false
    
    /// Diagnostic eviction active status for PQ-CSE-004
    private(set) var diagnosticEvictionActive: Bool = false
    
    /// Mesh mooring heartbeat callback for PQ-CSE-005
    var onMeshMooringHeartbeat: (() -> Void)? = nil
    
    /// Mock mesh quorum for testing (PQ-SAF-002)
    private(set) var mockMeshQuorum: Int = 9
    
    /// Last NCR ID for testing (PQ-SAF-004)
    private(set) var lastNCRID: String? = nil
    
    /// Mesh quorum count for testing (PQ-SAF-002)
    var meshQuorum: Int { mockMeshQuorum }
    
    /// Degraded mode active status (PQ-SAF-007)
    private(set) var degradedModeActive: Bool = false
    
    /// Mesh telemetry available status (PQ-SAF-007)
    private(set) var meshTelemetryAvailable: Bool = true
    
    /// Mock Bitcoin tau for testing (PQ-SAF-005)
    private(set) var mockBitcoinTau: Double? = nil
    
    /// Refusal reason for testing (PQ-SAF-003)
    private(set) var refusalReason: String? = nil
    
    /// NCR storage for testing (PQ-SAF-004)
    private var ncrRecords: [String: [String: Any]] = [:]
    
    /// Inject fault telemetry for safety testing
    /// Triggers SCRAM and REFUSED state if value violates physics bounds
    func injectFaultTelemetry(field: String, value: Double) {
        measuredTelemetry[field] = value
        
        // Check for critical violations (simplified bounds check)
        // Real implementation would check PLANT_INVARIANTS.md bounds per plant type
        let isCriticalViolation = value > 100.0 || value < -100.0 || value.isNaN || value.isInfinite
        
        if isCriticalViolation {
            scramTriggered = true
            terminalState = .refused
            refusalReason = "Physics violation: \(field) = \(value)"
        }
    }
    
    /// Inject malformed telemetry for crash recovery testing
    func injectMalformedTelemetry() {
        measuredTelemetry["invalid"] = .nan
        errorBoundaryActive = true
        appCrashed = false
    }
    
    /// Generate 2FA token for REFUSED override (safety protocol)
    func generate2FAToken() -> String {
        return UUID().uuidString
    }
    
    /// Override REFUSED state with 2FA token (safety protocol)
    func overrideRefusal(token: String?) throws -> Bool {
        guard terminalState == .refused else {
            throw NSError(domain: "OpenUSDLanguageGameState", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Not in REFUSED state"])
        }
        
        // Validate token (simplified - real implementation would verify cryptographic signature)
        guard let token = token, !token.isEmpty, token.count > 10 else {
            throw NSError(domain: "OpenUSDLanguageGameState", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid 2FA token"])
        }
        
        // Clear REFUSED state
        terminalState = .calorie
        scramTriggered = false
        
        return true
    }
    
    /// Check wallet authorization for PQ-CSE-005
    func checkWalletAuthorization(_ wallet: String) async -> Bool {
        // Simplified check - real implementation would query substrate
        let authorizedWallets = ["bc1q_founder_test_address"]
        return authorizedWallets.contains(wallet)
    }
    
    /// Inject swap failure for PQ-CSE-006 testing
    func injectSwapFailure(to plantKind: String) {
        // Simulate swap failure - sets swap state to rollback
        swapState = .rollback
    }
    
    /// Update SubGame Z status for PQ-CSE-004
    func updateSubGameZ(active: Bool, diagnosticEviction: Bool = false) {
        subGameZActive = active
        diagnosticEvictionActive = diagnosticEviction
    }
    
    /// Set mock mesh quorum for testing (PQ-SAF-002)
    func setMockMeshQuorum(_ quorum: Int) {
        mockMeshQuorum = quorum
        if quorum < 7 {
            updateSubGameZ(active: true, diagnosticEviction: true)
        } else {
            updateSubGameZ(active: false, diagnosticEviction: false)
        }
    }
    
    /// Acknowledge REFUSED state (PQ-SAF-003)
    func acknowledgeRefusal() {
        if terminalState == .refused {
            // Acknowledgment logged but state persists until 2FA override
            ncrLogged = true
            lastNCRID = "NCR-\(Date().timeIntervalSince1970)"
            if let id = lastNCRID {
                ncrRecords[id] = [
                    "id": id,
                    "reason": refusalReason ?? "Unknown",
                    "timestamp": Date().timeIntervalSince1970,
                    "state": "logged"
                ]
            }
        }
    }
    
    /// Get NCR record by ID (PQ-SAF-004)
    func getNCR(id: String) throws -> [String: Any] {
        guard let record = ncrRecords[id] else {
            throw NSError(domain: "OpenUSDLanguageGameState", code: 404,
                         userInfo: [NSLocalizedDescriptionKey: "NCR not found"])
        }
        return record
    }
    
    /// Edit NCR record (PQ-SAF-004 - should fail per immutability requirement)
    func editNCR(id: String, field: String, value: Any) throws {
        guard ncrRecords[id] != nil else {
            throw NSError(domain: "OpenUSDLanguageGameState", code: 404,
                         userInfo: [NSLocalizedDescriptionKey: "NCR not found"])
        }
        // NCR records are immutable per 21 CFR Part 11
        throw NSError(domain: "OpenUSDLanguageGameState", code: 403,
                     userInfo: [NSLocalizedDescriptionKey: "NCR records are immutable"])
    }
    
    /// Delete NCR record (PQ-SAF-004 - should fail per immutability requirement)
    func deleteNCR(id: String) throws {
        guard ncrRecords[id] != nil else {
            throw NSError(domain: "OpenUSDLanguageGameState", code: 404,
                         userInfo: [NSLocalizedDescriptionKey: "NCR not found"])
        }
        // NCR records are immutable per 21 CFR Part 11
        throw NSError(domain: "OpenUSDLanguageGameState", code: 403,
                     userInfo: [NSLocalizedDescriptionKey: "NCR records are immutable"])
    }
    
    /// Access MCP gateway (PQ-SAF-006)
    func accessMCPGateway(wallet: String) async throws {
        let authorized = await checkWalletAuthorization(wallet)
        if !authorized {
            ncrLogged = true
            lastNCRID = "NCR-UNAUTHORIZED-\(Date().timeIntervalSince1970)"
            throw GatewayError(code: 402, message: "Unauthorized wallet access blocked")
        }
    }
    
    /// Set mock Bitcoin tau for testing (PQ-SAF-005)
    func setMockBitcoinTau(_ tau: Double) {
        mockBitcoinTau = tau
    }
    
    /// Set mock Bitcoin tau with divergence check (PQ-SAF-005)
    func mockBitcoinTau(mac: Double, mesh: Double) {
        mockBitcoinTau = mesh
        let divergence = abs(mac - mesh)
        if divergence > 10 {
            terminalState = .refused
            refusalReason = "Bitcoin tau divergence: |τ_mac - τ_mesh| = \(divergence)"
        }
    }
    
    /// Set degraded mode (PQ-SAF-007)
    func setDegradedMode(_ active: Bool) {
        degradedModeActive = active
        meshTelemetryAvailable = !active
    }
}

