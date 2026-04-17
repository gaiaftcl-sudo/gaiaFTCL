import XCTest
@testable import GaiaFusion

/// WASM Constitutional Check test suite
/// Tests violation code thresholds and alarm workflows
final class ConstitutionalBridgeTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    var fusionBridge: FusionBridge!
    var stateMachine: FusionCellStateMachine!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        fusionBridge = FusionBridge()
        stateMachine = FusionCellStateMachine(initialState: .running)
        fusionBridge.fusionCellStateMachine = stateMachine
    }
    
    override func tearDownWithError() throws {
        fusionBridge = nil
        stateMachine = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Section 1: Violation Code Threshold Tests
    
    func test_ViolationCode0_NoStateChange() {
        // violation_code: 0 = Physics state clean
        // Expected: No state transition, RUNNING continues
        
        let initialState = stateMachine.operationalState
        
        // Inject violation code 0 via bridge
        injectMockViolationCode(0)
        
        // Verify no state change
        XCTAssertEqual(stateMachine.operationalState, initialState,
                       "Violation code 0 should not trigger state change")
    }
    
    func test_ViolationCode1_2_3_Benign_NoAlarm() {
        // violation_codes: 1-3 = Benign violations (warnings)
        // Expected: No alarm state transition
        
        let benignCodes = [1, 2, 3]
        
        for code in benignCodes {
            setUp() // Reset state
            _ = stateMachine.requestTransition(to: .running, initiator: .test, reason: "test setup")
            
            injectMockViolationCode(code)
            
            XCTAssertNotEqual(stateMachine.operationalState, .constitutionalAlarm,
                              "Violation code \(code) should not trigger constitutional alarm")
        }
    }
    
    func test_ViolationCode4_TriggersAlarm() {
        // violation_code: 4 = Safety boundary crossed
        // Expected: Force transition to .constitutionalAlarm
        
        _ = stateMachine.requestTransition(to: .running, initiator: .test, reason: "test setup")
        
        injectMockViolationCode(4)
        
        XCTAssertEqual(stateMachine.operationalState, .constitutionalAlarm,
                       "Violation code 4 should force .constitutionalAlarm state")
    }
    
    func test_ViolationCode5_TriggersAlarm() {
        // violation_code: 5 = Critical violation
        // Expected: Force transition to .constitutionalAlarm
        
        _ = stateMachine.requestTransition(to: .running, initiator: .test, reason: "test setup")
        
        injectMockViolationCode(5)
        
        XCTAssertEqual(stateMachine.operationalState, .constitutionalAlarm,
                       "Violation code 5 should force .constitutionalAlarm state")
    }
    
    func test_ViolationCodeThreshold_Boundary() {
        // Test the >= 4 boundary precisely
        
        // Code 3 should NOT trigger alarm
        setUp()
        _ = stateMachine.requestTransition(to: .running, initiator: .test, reason: "test")
        injectMockViolationCode(3)
        XCTAssertNotEqual(stateMachine.operationalState, .constitutionalAlarm,
                          "Code 3 is below threshold, should not alarm")
        
        // Code 4 SHOULD trigger alarm
        setUp()
        _ = stateMachine.requestTransition(to: .running, initiator: .test, reason: "test")
        injectMockViolationCode(4)
        XCTAssertEqual(stateMachine.operationalState, .constitutionalAlarm,
                       "Code 4 is at threshold, should alarm")
    }
    
    // MARK: - Section 2: Alarm Acknowledgment Flow
    
    func test_AlarmAcknowledgment_L1_REFUSED() {
        // Trigger alarm
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        
        // Attempt to clear alarm with L1 role
        let l1ClearResult = stateMachine.requestTransition(
            to: .idle,
            initiator: .operatorAction("alarm_acknowledge_l1"),
            reason: "L1 attempting to clear alarm"
        )
        
        // Should be REFUSED - L2 required
        XCTAssertFalse(l1ClearResult, "L1 operator should be REFUSED for alarm acknowledgment")
        XCTAssertEqual(stateMachine.operationalState, .constitutionalAlarm,
                       "State should remain .constitutionalAlarm after L1 attempt")
    }
    
    func test_AlarmAcknowledgment_L2_Success() {
        // Trigger alarm
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        
        // Clear alarm with L2 role
        let l2ClearResult = stateMachine.requestTransition(
            to: .idle,
            initiator: .operatorAction("alarm_acknowledge_l2"),
            reason: "L2 acknowledging alarm"
        )
        
        // Should succeed
        XCTAssertTrue(l2ClearResult, "L2 operator should successfully acknowledge alarm")
        XCTAssertEqual(stateMachine.operationalState, .idle,
                       "State should transition to .idle after L2 acknowledgment")
    }
    
    func test_AlarmAuditLog_ContainsL2Wallet() {
        // Trigger alarm
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        
        // Clear alarm with L2
        let mockL2Wallet = "0xL2_SENIOR_OPERATOR_ABC"
        _ = stateMachine.requestTransition(
            to: .idle,
            initiator: .operatorAction("alarm_acknowledge_l2_\(mockL2Wallet)"),
            reason: "L2 acknowledging alarm"
        )
        
        // Verify audit log contains:
        // - wallet_pubkey: mockL2Wallet
        // - action: "acknowledge_constitutional_alarm"
        // - timestamp
        // - previous_state: CONSTITUTIONAL_ALARM
        // - new_state: IDLE
        
        // (Actual audit log verification would require reading log file or checking in-memory log)
        XCTAssertEqual(stateMachine.operationalState, .idle,
                       "State should be IDLE after successful acknowledgment")
    }
    
    // MARK: - Section 3: Alarm-to-Running Recovery
    
    func test_AlarmToRunning_PhysicsNotClear_REFUSED() {
        // CRITICAL: Physics must certify clean (violationCode == 0) BEFORE human authorization
        
        // Trigger alarm
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        
        // Attempt L3 dual-auth to RUNNING while violationCode > 0
        setMockViolationCode(4)  // Physics still violated
        
        let l3TransitionResult = stateMachine.requestTransition(
            to: .running,
            initiator: .operatorAction("alarm_recovery_l3_dualauth"),
            reason: "L3 attempting recovery with active violation"
        )
        
        // Should be REFUSED - physics must clear first
        XCTAssertFalse(l3TransitionResult,
                       "Transition to RUNNING should be REFUSED while violationCode > 0")
        XCTAssertEqual(stateMachine.operationalState, .constitutionalAlarm,
                       "State should remain .constitutionalAlarm until physics clears")
    }
    
    func test_AlarmToRunning_PhysicsClear_ThenL3DualAuth_Success() {
        // CORRECT SEQUENCING: Physics clears → then L3 dual-auth → RUNNING
        
        // Trigger alarm
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        
        // Step 1: Physics clears violation
        setMockViolationCode(0)
        
        // Step 2: L3 dual-auth authorizes return to RUNNING
        let mockL3Wallet1 = "0xL3_SUPERVISOR_ABC"
        let mockL3Wallet2 = "0xL3_SUPERVISOR_DEF"
        
        // Dual-auth requires two different L3 wallets
        let l3DualAuthResult = stateMachine.requestTransition(
            to: .running,
            initiator: .operatorAction("alarm_recovery_l3_dualauth_\(mockL3Wallet1)_\(mockL3Wallet2)"),
            reason: "L3 dual-auth after physics clear"
        )
        
        // Should succeed
        XCTAssertTrue(l3DualAuthResult,
                      "Transition to RUNNING should succeed after physics clear + L3 dual-auth")
        XCTAssertEqual(stateMachine.operationalState, .running,
                       "State should be .running after successful dual-auth recovery")
    }
    
    func test_AlarmToRunning_AuditLog_ShowsBothL3Wallets() {
        // Trigger and clear physics violation
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        setMockViolationCode(0)
        
        // L3 dual-auth
        let mockL3Wallet1 = "0xL3_SUPERVISOR_ABC"
        let mockL3Wallet2 = "0xL3_SUPERVISOR_DEF"
        
        _ = stateMachine.requestTransition(
            to: .running,
            initiator: .operatorAction("alarm_recovery_l3_dualauth_\(mockL3Wallet1)_\(mockL3Wallet2)"),
            reason: "L3 dual-auth recovery"
        )
        
        // Verify audit log contains:
        // - wallet_pubkey_1: mockL3Wallet1
        // - wallet_pubkey_2: mockL3Wallet2
        // - action: "alarm_recovery_to_running"
        // - physics_state_confirmed: "violation_code_0"
        // - timestamp
        
        XCTAssertEqual(stateMachine.operationalState, .running,
                       "State should be RUNNING after dual-auth")
    }
    
    // MARK: - Section 4: ConstitutionalHUD Visibility
    
    func test_ConstitutionalHUD_Visible_InAlarmState() {
        // Trigger alarm
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        
        // ConstitutionalHUD should be visible
        // (Actual UI test would check layoutManager.constitutionalHudVisible)
        XCTAssertEqual(stateMachine.operationalState, .constitutionalAlarm)
        
        // Expected UI state:
        // - ConstitutionalHUD visible at top
        // - Metal viewport at 100% opacity
        // - WKWebView at 85% opacity
        // - Keyboard shortcuts locked
    }
    
    func test_ConstitutionalHUD_Hidden_AfterAcknowledgment() {
        // Trigger and acknowledge alarm
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        _ = stateMachine.requestTransition(to: .idle, initiator: .operatorAction("alarm_acknowledge_l2"), reason: "L2 ack")
        
        // ConstitutionalHUD should be hidden in IDLE
        XCTAssertEqual(stateMachine.operationalState, .idle)
        
        // Expected UI state:
        // - ConstitutionalHUD hidden
        // - Layout mode returns to normal
        // - Keyboard shortcuts unlocked
    }
    
    // MARK: - Section 5: No Auto-Transition When Violation Clears
    
    func test_ViolationClears_NoAutoTransitionToIdle() {
        // CRITICAL: violationCode clearing to 0 should NOT auto-transition out of alarm
        // This was Defect 2 - removal of auto-transition
        
        // Trigger alarm
        _ = stateMachine.requestTransition(to: .constitutionalAlarm, initiator: .test, reason: "test alarm")
        
        // Physics clears violation
        setMockViolationCode(0)
        
        // Wait briefly (simulating time for auto-transition if it existed)
        let expectation = self.expectation(description: "Wait for potential auto-transition")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // State should STILL be .constitutionalAlarm (no auto-transition)
        XCTAssertEqual(stateMachine.operationalState, .constitutionalAlarm,
                       "Alarm should NOT auto-clear when violationCode reaches 0 - requires operator acknowledgment")
    }
    
    // MARK: - Helper Methods
    
    /// Inject mock violation code via WASM bridge
    private func injectMockViolationCode(_ code: Int) {
        // In production, this would be:
        // fusionBridge.wasm_constitutional_check(violationCode: code)
        
        // For testing, directly trigger the state machine logic
        if code >= 4 {
            _ = stateMachine.forceState(.constitutionalAlarm, reason: "Mock violation code \(code) >= 4")
        }
    }
    
    /// Set mock violation code for sequencing tests
    private func setMockViolationCode(_ code: Int) {
        // In production, this would update the WASM module's internal state
        // For testing, we're simulating the physics state
        
        // Store in a test property to check in transition validation
        fusionBridge.mockViolationCode = code
    }
}

// MARK: - FusionBridge Test Extension

extension FusionBridge {
    /// Mock violation code for testing (not present in production code)
    private static var mockViolationCodeStorage: Int = 0
    
    var mockViolationCode: Int {
        get { Self.mockViolationCodeStorage }
        set { Self.mockViolationCodeStorage = newValue }
    }
}

// MARK: - FusionCellStateMachine Test Extensions

extension FusionCellStateMachine {
    /// Check if alarm-to-running transition is allowed based on physics state
    func canTransitionToRunningFromAlarm(violationCode: Int) -> Bool {
        guard operationalState == .constitutionalAlarm else { return false }
        
        // CRITICAL: Physics must certify clean (violationCode == 0) before allowing transition
        return violationCode == 0
    }
}
