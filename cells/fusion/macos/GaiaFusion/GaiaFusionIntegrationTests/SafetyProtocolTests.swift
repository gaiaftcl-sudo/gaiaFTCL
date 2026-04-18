import XCTest
@testable import GaiaFusion

/// Safety Protocol Integration Tests
/// These are NOT unit tests — they test against REAL infrastructure
/// Zero mock rule: uses LiveMeshConnector with shortened timeouts
@MainActor
final class SafetyProtocolTests: XCTestCase {
    
    // MARK: - SP-002: Mooring Degradation (Designed Death Test)
    
    func testMooringDegradationRealInfrastructure() async throws {
        // Set shortened timeout for test (10 seconds instead of 1 hour)
        setenv("GAIAFUSION_MOORING_TIMEOUT_SECONDS", "10", 1)
        
        let coordinator = AppCoordinator(meshConnector: LiveMeshConnector())
        
        // Transition to MOORED
        try await coordinator.transitionTo(.moored, initiator: .test)
        
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .moored, "Should be in MOORED state")
        
        // Trigger real NATS disconnect via external script
        let disconnectScript = Bundle(for: type(of: self)).path(forResource: "disconnect_test_nats", ofType: "sh")!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [disconnectScript]
        
        try process.run()
        process.waitUntilExit()
        
        XCTAssertEqual(process.terminationStatus, 0, "NATS disconnect script must succeed")
        
        // Wait for real timer to fire (10 seconds + buffer)
        try await Task.sleep(for: .seconds(12))
        
        // Verify designed death occurred
        let finalState = coordinator.fusionCellStateMachine.operationalState
        XCTAssertNotEqual(finalState, .moored, "System must degrade after timeout")
        XCTAssertTrue(
            [PlantOperationalState.tripped, .constitutionalAlarm, .idle].contains(finalState),
            "Final state must be TRIPPED, CONSTITUTIONAL_ALARM, or IDLE after degradation"
        )
        
        XCTAssertTrue(coordinator.mooringDegradationOccurred, "Degradation flag must be set")
        
        // Clean up
        unsetenv("GAIAFUSION_MOORING_TIMEOUT_SECONDS")
    }
    
    // MARK: - SP-003: Abnormal State Lockdown
    
    func testAbnormalStateLockdown() async throws {
        let coordinator = AppCoordinator()
        
        // Transition to RUNNING
        try await coordinator.transitionTo(.idle)
        try await coordinator.transitionTo(.moored)
        try await coordinator.transitionTo(.running)
        
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .running)
        
        // Verify keyboard shortcuts disabled in RUNNING
        XCTAssertFalse(coordinator.fusionCellStateMachine.operationalState.keyboardShortcutsEnabled,
                       "Keyboard shortcuts must be disabled in RUNNING state")
        
        // Force TRIPPED state
        try await coordinator.transitionTo(.tripped, initiator: .automatic)
        
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .tripped)
        XCTAssertFalse(coordinator.fusionCellStateMachine.operationalState.keyboardShortcutsEnabled,
                       "Keyboard shortcuts must be disabled in TRIPPED state")
        
        // Verify only allowed actions work
        XCTAssertTrue(coordinator.fusionCellStateMachine.operationalState.allows(action: .resetTrip),
                      "Reset trip must be allowed in TRIPPED state")
        XCTAssertFalse(coordinator.fusionCellStateMachine.operationalState.allows(action: .swapPlant),
                       "Plant swap must NOT be allowed in TRIPPED state")
    }
    
    // MARK: - SP-004: Default State Verification
    
    func testDefaultStateVerification() async throws {
        let coordinator = AppCoordinator()
        
        // Verify initial state is IDLE
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .idle,
                       "Clean launch must start in IDLE state")
    }
    
    // MARK: - State Transition Validation
    
    func testValidStateTransitions() async throws {
        let coordinator = AppCoordinator()
        
        // Test valid transition chain: IDLE → MOORED → RUNNING
        try await coordinator.transitionTo(.moored)
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .moored)
        
        try await coordinator.transitionTo(.running)
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .running)
        
        // Test RUNNING → TRIPPED
        try await coordinator.transitionTo(.tripped, initiator: .automatic)
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .tripped)
        
        // Test TRIPPED → IDLE
        try await coordinator.transitionTo(.idle)
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .idle)
    }
    
    func testInvalidStateTransitions() async throws {
        let coordinator = AppCoordinator()
        
        // Try invalid transition: IDLE → RUNNING (must go through MOORED)
        do {
            try await coordinator.transitionTo(.running)
            XCTFail("Should not allow IDLE → RUNNING transition")
        } catch CoordinatorError.invalidStateTransition {
            // Expected
        }
        
        // Verify state unchanged
        XCTAssertEqual(coordinator.fusionCellStateMachine.operationalState, .idle)
    }
    
    // MARK: - State File Writing
    
    func testStateFileWriting() async throws {
        let coordinator = AppCoordinator()
        
        // Transition to MOORED
        try await coordinator.transitionTo(.moored)
        
        // Give file system time to write
        try await Task.sleep(for: .seconds(1))
        
        // Verify state file exists and contains correct state
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let stateFile = appSupport.appendingPathComponent("GaiaFusion/state.json")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateFile.path), "State file must exist")
        
        let data = try Data(contentsOf: stateFile)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["currentState"] as? String, "MOORED", "State file must reflect current state")
        XCTAssertNotNil(json?["lastTransitionTimestamp"], "Must have timestamp")
        XCTAssertNotNil(json?["uptimeSeconds"], "Must have uptime")
    }
}
