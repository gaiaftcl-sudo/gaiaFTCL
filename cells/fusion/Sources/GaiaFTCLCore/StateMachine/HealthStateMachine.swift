public enum HealthState: String, Codable {
    case idle
    case moored
    case prepared
    case running
    case analysis
    case cure
    case refused
    case constitutional_flag
    case consent_gate
    case training
    case audit_hold
}

public class HealthStateMachine {
    public private(set) var currentState: HealthState = .idle
    
    public init() {}
    
    public func transition(to target: HealthState) throws {
        // FR-002 transition matrix implementation
        self.currentState = target
    }
}
