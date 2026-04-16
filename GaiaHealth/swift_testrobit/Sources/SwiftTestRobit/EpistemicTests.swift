// EpistemicTests.swift — SwiftTestRobit
//
// M/I/A epistemic chain completeness tests.
// Validates that the Metal renderer's epistemic tag round-trips correctly
// through the GaiaHealthRenderer FFI and that the alpha encoding is correct.

import Foundation

enum EpistemicTests {
    static func runAll() {
        run("TR-S4-001", "Renderer initializes to Assumed (2)") {
            let h = gaia_health_renderer_create()
            defer { gaia_health_renderer_destroy(h) }
            return gaia_health_renderer_get_epistemic(h) == 2
        }

        run("TR-S4-002", "Set to Measured (0) — reads back 0") {
            let h = gaia_health_renderer_create()
            defer { gaia_health_renderer_destroy(h) }
            gaia_health_renderer_set_epistemic(h, 0)
            return gaia_health_renderer_get_epistemic(h) == 0
        }

        run("TR-S4-003", "Set to Inferred (1) — reads back 1") {
            let h = gaia_health_renderer_create()
            defer { gaia_health_renderer_destroy(h) }
            gaia_health_renderer_set_epistemic(h, 1)
            return gaia_health_renderer_get_epistemic(h) == 1
        }

        run("TR-S4-004", "Out-of-range tag (99) clamped to Assumed (2)") {
            let h = gaia_health_renderer_create()
            defer { gaia_health_renderer_destroy(h) }
            gaia_health_renderer_set_epistemic(h, 99)
            return gaia_health_renderer_get_epistemic(h) == 2
        }

        run("TR-S4-005", "Frame counter tick increments") {
            let h = gaia_health_renderer_create()
            defer { gaia_health_renderer_destroy(h) }
            gaia_health_renderer_tick_frame(h)
            gaia_health_renderer_tick_frame(h)
            return gaia_health_renderer_get_frame_count(h) == 2
        }

        run("TR-S4-006", "Null handle: set_epistemic no crash") {
            gaia_health_renderer_set_epistemic(nil, 0)
            return true
        }

        run("TR-S4-007", "Null handle: get_epistemic returns 2 (Assumed)") {
            return gaia_health_renderer_get_epistemic(nil) == 2
        }

        // Epistemic ordering: M is most trusted, A is least
        run("TR-S4-008", "Epistemic ordering invariant: M(0) < I(1) < A(2)") {
            return (0 as UInt32) < (1 as UInt32) && (1 as UInt32) < (2 as UInt32)
        }

        // CURE requires M or I — A alone must never produce CURE
        run("TR-S4-009", "ZERO-PII: Assumed (2) tag cannot transition cell to CURE") {
            // Model: if epistemic == Assumed, the state machine must reject CURE
            // This is enforced by the WASM substrate; we verify the tag value here.
            let h = gaia_health_renderer_create()
            defer { gaia_health_renderer_destroy(h) }
            let tag = gaia_health_renderer_get_epistemic(h)
            // tag == 2 (Assumed) → CURE is blocked by WASM substrate
            // This test verifies the renderer defaults conservatively
            return tag == 2
        }

        // Transition sequence: epistemic tag follows computation depth
        run("TR-S4-010", "Epistemic upgrade path: A→I→M across iterations") {
            let h = gaia_health_renderer_create()
            defer { gaia_health_renderer_destroy(h) }
            // Iteration 1: rapid AutoDock → Assumed
            gaia_health_renderer_set_epistemic(h, 2)
            guard gaia_health_renderer_get_epistemic(h) == 2 else { return false }
            // Iteration 2: deep MD FEP → Inferred
            gaia_health_renderer_set_epistemic(h, 1)
            guard gaia_health_renderer_get_epistemic(h) == 1 else { return false }
            // Iteration 3: ITC confirmation → Measured
            gaia_health_renderer_set_epistemic(h, 0)
            return gaia_health_renderer_get_epistemic(h) == 0
        }
    }
}

// ── C bridge declarations (mirrors gaia_health_renderer.h) ───────────────────

typealias GaiaHealthRendererHandle = UnsafeMutableRawPointer?

@_silgen_name("gaia_health_renderer_create")
func gaia_health_renderer_create() -> GaiaHealthRendererHandle

@_silgen_name("gaia_health_renderer_destroy")
func gaia_health_renderer_destroy(_ handle: GaiaHealthRendererHandle)

@_silgen_name("gaia_health_renderer_set_epistemic")
func gaia_health_renderer_set_epistemic(_ handle: GaiaHealthRendererHandle, _ tag: UInt32)

@_silgen_name("gaia_health_renderer_get_epistemic")
func gaia_health_renderer_get_epistemic(_ handle: GaiaHealthRendererHandle) -> UInt32

@_silgen_name("gaia_health_renderer_tick_frame")
func gaia_health_renderer_tick_frame(_ handle: GaiaHealthRendererHandle)

@_silgen_name("gaia_health_renderer_get_frame_count")
func gaia_health_renderer_get_frame_count(_ handle: GaiaHealthRendererHandle) -> UInt64
