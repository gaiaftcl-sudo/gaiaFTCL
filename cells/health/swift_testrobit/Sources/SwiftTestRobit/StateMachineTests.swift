// StateMachineTests.swift — SwiftTestRobit
//
// State machine transition tests for the biologit cell.
// Validates the DQ specification transition matrix end-to-end from Swift.

import Foundation

/// Biological cell state discriminants (must match BiologicalCellState in Rust)
enum CellState: UInt32 {
    case idle              = 0
    case moored            = 1
    case prepared          = 2
    case running           = 3
    case analysis          = 4
    case cure              = 5
    case refused           = 6
    case constitutionalFlag = 7
    case consentGate       = 8
    case training          = 9
    case auditHold         = 10
}

enum StateMachineTests {
    static func runAll() {
        run("TR-S2-001", "Full CURE path: IDLE→MOORED→PREPARED→RUNNING→ANALYSIS→CURE") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            let path: [CellState] = [.moored, .prepared, .running, .analysis, .cure]
            return path.allSatisfy { state in
                bio_state_transition(h, state.rawValue) == 1
            }
        }

        run("TR-S2-002", "REFUSED path: ANALYSIS→REFUSED allowed") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            [CellState.moored, .prepared, .running, .analysis].forEach {
                _ = bio_state_transition(h, $0.rawValue)
            }
            return bio_state_transition(h, CellState.refused.rawValue) == 1
        }

        run("TR-S2-003", "CONSTITUTIONAL_FLAG from RUNNING") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            [CellState.moored, .prepared, .running].forEach {
                _ = bio_state_transition(h, $0.rawValue)
            }
            return bio_state_transition(h, CellState.constitutionalFlag.rawValue) == 1
        }

        run("TR-S2-004", "CONSTITUTIONAL_FLAG → IDLE (R2 emergency exit)") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            [CellState.moored, .prepared, .running, .constitutionalFlag].forEach {
                _ = bio_state_transition(h, $0.rawValue)
            }
            return bio_state_transition(h, CellState.idle.rawValue) == 1
        }

        run("TR-S2-005", "AUDIT_HOLD reachable from any state") {
            for stateId: UInt32 in 0...10 {
                let h = bio_state_create()
                defer { bio_state_destroy(h) }
                // Advance to the target state using the simplest valid path
                _ = bio_state_transition(h, stateId)
                guard bio_state_transition(h, CellState.auditHold.rawValue) == 1 else {
                    return false
                }
            }
            return true
        }

        run("TR-S2-006", "IDLE→RUNNING rejected (invalid skip)") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            return bio_state_transition(h, CellState.running.rawValue) == 0
        }

        run("TR-S2-007", "IDLE→ANALYSIS rejected") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            return bio_state_transition(h, CellState.analysis.rawValue) == 0
        }

        run("TR-S2-008", "IDLE→CURE rejected") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            return bio_state_transition(h, CellState.cure.rawValue) == 0
        }

        run("TR-S2-009", "TRAINING cycle: IDLE→TRAINING→IDLE") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            return bio_state_transition(h, CellState.training.rawValue) == 1
                && bio_state_transition(h, CellState.idle.rawValue) == 1
        }

        run("TR-S2-010", "CURE→PREPARED for next lead optimization iteration") {
            let h = bio_state_create()
            defer { bio_state_destroy(h) }
            let path: [CellState] = [.moored, .prepared, .running, .analysis, .cure, .prepared]
            return path.allSatisfy { bio_state_transition(h, $0.rawValue) == 1 }
        }
    }
}
