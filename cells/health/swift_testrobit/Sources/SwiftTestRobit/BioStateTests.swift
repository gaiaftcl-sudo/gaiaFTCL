// BioStateTests.swift — SwiftTestRobit
//
// FFI bridge tests for the biologit_md_engine Rust static library.
// Exercises bio_state_create / destroy / get_state / transition / moor_owl.
//
// All tests run in training_mode=true — no PHI proximity.

import Foundation

enum BioStateTests {
    static func runAll() {
        run("TR-S1-001", "bio_state_create returns non-null handle") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            return handle != nil
        }

        run("TR-S1-002", "Initial state is IDLE (0)") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            return bio_state_get_state(handle) == 0
        }

        run("TR-S1-003", "bio_state_transition IDLE→MOORED returns 1 (allowed)") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            return bio_state_transition(handle, 1) == 1 // 1 = MOORED
        }

        run("TR-S1-004", "bio_state_transition IDLE→RUNNING returns 0 (rejected)") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            return bio_state_transition(handle, 3) == 0 // 3 = RUNNING — invalid skip
        }

        run("TR-S1-005", "Frame counter increments correctly") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            bio_state_increment_frame(handle)
            bio_state_increment_frame(handle)
            bio_state_increment_frame(handle)
            return bio_state_get_frame_count(handle) == 3
        }

        run("TR-S1-006", "Epistemic tag defaults to 2 (Assumed)") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            return bio_state_get_epistemic_tag(handle) == 2
        }

        run("TR-S1-007", "bio_state_moor_owl accepts valid secp256k1 pubkey") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            let pk = "02a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
            var bytes = Array(pk.utf8)
            return bio_state_moor_owl(handle, &bytes, bytes.count) == 1
        }

        // Zero-PII critical tests
        run("TR-S1-008", "ZERO-PII: moor_owl rejects email address") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            let email = "patient@example.com"
            var bytes = Array(email.utf8)
            return bio_state_moor_owl(handle, &bytes, bytes.count) == 0
        }

        run("TR-S1-009", "ZERO-PII: moor_owl rejects patient name") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            let name = "John Doe"
            var bytes = Array(name.utf8)
            return bio_state_moor_owl(handle, &bytes, bytes.count) == 0
        }

        run("TR-S1-010", "ZERO-PII: IDLE transition zeroes frame count") {
            let handle = bio_state_create()
            defer { bio_state_destroy(handle) }
            let toMoored = bio_state_transition(handle, 1) // → MOORED
            guard toMoored == 1 else { return false } // transition must succeed
            bio_state_increment_frame(handle)
            let toIdle = bio_state_transition(handle, 0) // → IDLE (zero-PII cleanup)
            guard toIdle == 1 else { return false } // transition must succeed
            return bio_state_get_frame_count(handle) == 0
        }

        run("TR-S1-011", "Null handle: get_state returns 0 without crash") {
            return bio_state_get_state(nil) == 0
        }

        run("TR-S1-012", "Null handle: transition returns 0 without crash") {
            return bio_state_transition(nil, 1) == 0
        }
    }
}

// ── C bridge declarations (mirrors gaia_health_engine.h) ─────────────────────

typealias BioStateHandle = UnsafeMutableRawPointer?

@_silgen_name("bio_state_create")
func bio_state_create() -> BioStateHandle

@_silgen_name("bio_state_destroy")
func bio_state_destroy(_ handle: BioStateHandle)

@_silgen_name("bio_state_get_state")
func bio_state_get_state(_ handle: BioStateHandle) -> UInt32

@_silgen_name("bio_state_get_frame_count")
func bio_state_get_frame_count(_ handle: BioStateHandle) -> UInt64

@_silgen_name("bio_state_increment_frame")
func bio_state_increment_frame(_ handle: BioStateHandle)

@_silgen_name("bio_state_get_epistemic_tag")
func bio_state_get_epistemic_tag(_ handle: BioStateHandle) -> UInt32

@_silgen_name("bio_state_transition")
func bio_state_transition(_ handle: BioStateHandle, _ target_state: UInt32) -> UInt32

@_silgen_name("bio_state_moor_owl")
func bio_state_moor_owl(_ handle: BioStateHandle, _ pubkey_ptr: UnsafePointer<UInt8>?, _ len: Int) -> UInt32
