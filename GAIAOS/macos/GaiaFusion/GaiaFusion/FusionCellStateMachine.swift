import Foundation

/// Operator authorization levels
/// Per OPERATOR_AUTHORIZATION_MATRIX.md Section 1
enum OperatorRole: String, Codable {
    case l1 = "L1"  // Operator — monitor telemetry, emergency stop, basic actions
    case l2 = "L2"  // Senior Operator — L1 + parameter changes, shot initiation, plant swap
    case l3 = "L3"  // Supervisor — L2 + maintenance mode, authorization settings, dual-auth approval
    
    /// Check if this role is at least as privileged as the required level
    func isAtLeast(_ required: OperatorRole) -> Bool {
        let hierarchy: [OperatorRole: Int] = [.l1: 1, .l2: 2, .l3: 3]
        return (hierarchy[self] ?? 0) >= (hierarchy[required] ?? 99)
    }
}

/// Plant operational states for fusion cell control
/// Per FUSION_CELL_OPERATIONAL_REQUIREMENTS.md Section 2
enum PlantOperationalState: String, Codable {
    case idle = "IDLE"
    case moored = "MOORED"
    case running = "RUNNING"
    case tripped = "TRIPPED"
    case constitutionalAlarm = "CONSTITUTIONAL_ALARM"
    case maintenance = "MAINTENANCE"
    case training = "TRAINING"
    
    /// Check if this state allows layout mode override by operator
    var allowsLayoutModeOverride: Bool {
        switch self {
        case .idle, .moored, .maintenance, .training:
            return true
        case .running, .tripped, .constitutionalAlarm:
            return false
        }
    }
    
    /// Check if keyboard shortcuts should be enabled in this state
    var keyboardShortcutsEnabled: Bool {
        switch self {
        case .idle, .moored, .maintenance, .training:
            return true
        case .running, .tripped, .constitutionalAlarm:
            return false
        }
    }
    
    /// Check if a specific action is allowed in this state
    func allows(action: FusionCellAction) -> Bool {
        switch action {
        case .armIgnition:
            return self == .moored
        case .emergencyStop:
            return self == .running
        case .resetTrip:
            return self == .tripped
        case .acknowledgeAlarm:
            return self == .constitutionalAlarm
        case .swapPlant:
            return self == .idle || self == .maintenance
        case .enterMaintenance:
            return self == .idle
        case .enterTraining:
            return self == .idle
        case .openConfig:
            return self == .idle || self == .maintenance
        }
    }
}

/// Actions that can be performed on the fusion cell
enum FusionCellAction {
    case armIgnition
    case emergencyStop
    case resetTrip
    case acknowledgeAlarm
    case swapPlant
    case enterMaintenance
    case enterTraining
    case openConfig
}

/// State transition initiator (operator or automatic)
enum StateTransitionInitiator {
    case operatorAction(String)  // operator ID
    case automatic
    case wasm
}

/// State machine for fusion cell operational states
/// Enforces valid transitions and logs all attempts
@MainActor
final class FusionCellStateMachine: ObservableObject {
    @Published private(set) var operationalState: PlantOperationalState = .idle
    
    /// Valid state transitions (from → to)
    private let validTransitions: Set<StateTransition> = [
        // From IDLE
        StateTransition(from: .idle, to: .moored),
        StateTransition(from: .idle, to: .training),
        StateTransition(from: .idle, to: .maintenance),
        
        // From MOORED
        StateTransition(from: .moored, to: .idle),
        StateTransition(from: .moored, to: .running),
        StateTransition(from: .moored, to: .tripped),
        
        // From RUNNING
        StateTransition(from: .running, to: .tripped),
        StateTransition(from: .running, to: .constitutionalAlarm),
        StateTransition(from: .running, to: .idle),
        
        // From TRIPPED
        StateTransition(from: .tripped, to: .idle),
        StateTransition(from: .tripped, to: .moored),
        
        // From CONSTITUTIONAL_ALARM
        StateTransition(from: .constitutionalAlarm, to: .idle),
        StateTransition(from: .constitutionalAlarm, to: .tripped),
        
        // From MAINTENANCE
        StateTransition(from: .maintenance, to: .idle),
        
        // From TRAINING
        StateTransition(from: .training, to: .idle),
    ]
    
    /// Request a state transition
    /// Returns true if transition succeeded, false if invalid
    @discardableResult
    func requestTransition(
        to newState: PlantOperationalState,
        initiator: StateTransitionInitiator,
        reason: String
    ) -> Bool {
        let transition = StateTransition(from: operationalState, to: newState)
        
        guard validTransitions.contains(transition) else {
            logTransitionAttempt(
                from: operationalState,
                to: newState,
                initiator: initiator,
                reason: reason,
                success: false,
                rejectionReason: "Invalid transition"
            )
            return false
        }
        
        // Transition is valid
        let oldState = operationalState
        operationalState = newState
        
        logTransitionAttempt(
            from: oldState,
            to: newState,
            initiator: initiator,
            reason: reason,
            success: true,
            rejectionReason: nil
        )
        
        return true
    }
    
    /// Force a state (used by WASM substrate only)
    /// Bypasses transition validation
    func forceState(_ newState: PlantOperationalState) {
        let oldState = operationalState
        operationalState = newState
        
        logTransitionAttempt(
            from: oldState,
            to: newState,
            initiator: .wasm,
            reason: "WASM substrate forced state",
            success: true,
            rejectionReason: nil
        )
    }
    
    /// Log transition attempt to audit system
    private func logTransitionAttempt(
        from oldState: PlantOperationalState,
        to newState: PlantOperationalState,
        initiator: StateTransitionInitiator,
        reason: String,
        success: Bool,
        rejectionReason: String?
    ) {
        let entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "action": "STATE_TRANSITION_\(success ? "SUCCESS" : "REJECTED")",
            "from_state": oldState.rawValue,
            "to_state": newState.rawValue,
            "initiator": initiatorString(initiator),
            "reason": reason,
            "success": success,
            "rejection_reason": rejectionReason ?? "",
        ]
        
        // TODO: Wire to actual audit log system
        print("🔐 AUDIT: \(entry)")
    }
    
    private func initiatorString(_ initiator: StateTransitionInitiator) -> String {
        switch initiator {
        case .operatorAction(let id):
            return "operator:\(id)"
        case .automatic:
            return "automatic"
        case .wasm:
            return "wasm_substrate"
        }
    }
}

/// Helper struct for state transition validation
private struct StateTransition: Hashable {
    let from: PlantOperationalState
    let to: PlantOperationalState
}
