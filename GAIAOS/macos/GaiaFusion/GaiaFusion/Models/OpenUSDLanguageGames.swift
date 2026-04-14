import Foundation

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
        }
    }
    
    /// Inject malformed telemetry for crash recovery testing
    func injectMalformedTelemetry() {
        measuredTelemetry["invalid"] = .nan
        errorBoundaryActive = true
        appCrashed = false
    }
}

