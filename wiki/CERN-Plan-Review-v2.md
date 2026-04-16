# CERN Plan Review — v2

## Assessment of Cursor's Revised Gap-Finding Plan

**FortressAI Research Institute | Norwich, Connecticut**
**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

> This document reviews Cursor's corrected CERN UI gap-finding plan against the actual GAIAFTCL Rust source. It accepts what the revision got right, corrects one significant framing error, and adds what is still missing. This is the authoritative synthesis for briefing the implementation team.

---

## Overall Verdict on the Revised Plan

The revised plan is a substantial improvement over the original. The corrected priority structure is directionally right. The WASM module must be fixed before the 12 PQ-UI tests can pass, and the two together must exist before geometry work is fully testable. However, the plan contains one framing error that will mislead the team on the constitutional architecture, and it still carries two unresolved gaps from the original.

**What to accept from the revised plan: 80%.**
**What to correct: the "life safety" framing of the WASM module.**
**What is still missing: the FFI extension gap and the standalone binary architecture gap.**

---

## Part 1: What the Revised Plan Gets Right

### 1.1 The P0/P1 Priority Reorder Is Correct in Sequence

Cursor's revised sequence — WASM first, then geometry — is the right execution order, even if the stated reason is partially wrong (see Part 2). The WASM module must exist and export the five required UUM-8D functions before the PQ-UI test suite can pass even a single test. The geometry work produces visual output that the tests then exercise. You cannot run PQ-UI-002 (terminal badge = CALORIE) without a working `compute_vqbit()` in WASM. You cannot run PQ-UI-001 (plant swap < 16.7ms) without real plant geometries to swap.

The practical execution order Cursor now proposes — fix WASM constitutional validation → verify vertex color pipeline → build nine plant geometries → extend FFI → write PQ-UI tests → write `pq_validate.sh` — is correct.

### 1.2 The WASM Build Specification Is Correct

The five required WASM exports match the composite app requirements exactly:

```rust
compute_vqbit(entropy: f32, truth: f32, plant_kind: u32) → JsValue
compute_closure_residual(i_p: f64, b_t: f64, n_e: f64, plant_kind: u32) → f64
validate_bounds(i_p: f64, b_t: f64, n_e: f64, plant_kind: u32) → u32
get_epistemic_tag(channel: u32, plant_kind: u32) → u32
constitutional_check(i_p: f64, b_t: f64, n_e: f64) → u32
```

The `wasm-bindgen` build pipeline is correct: `cargo build --target wasm32-unknown-unknown --release` followed by `wasm-bindgen` to produce the JS bindings. The verification method (browser console, check `typeof wasm.function_name === 'function'`) is correct.

One addition needed: `constitutional_check` must handle NaN and Inf as inputs without panicking. The WASM sandbox does not give you a Rust panic handler in the same way as a native binary. Add `#[allow(clippy::float_cmp)]` and explicit NaN/Inf detection before any arithmetic.

### 1.3 Vertex Color Pipeline Verification Is a Valid Addition

Cursor added a new item that the original plan and this audit both missed: **verify the full WKWebView → WASM → Rust → Metal vertex colour pipeline is live and completes within one frame budget.** This is the correct way to validate that the real-time telemetry feed is working end-to-end, not just that each component passes its unit tests in isolation. The test method (inject known I_p/B_T/n_e values, verify vertex colours update) is the right approach.

The `shaders.rs` in the GAIAFTCL repository confirms the Metal shader passes vertex colours through directly — `fragment_main` returns `in.color` without modification. The vertex colour encoding (R = `vqbit_entropy`, G = `vqbit_truth`, B = 0.5 hardcoded, A = 1.0 hardcoded) is implemented in `renderer.rs` `upload_geometry_from_primitives()`. The pipeline architecture is correct. What has not been verified is the end-to-end latency under real message traffic.

### 1.4 Geometry Generation Strategy Is Correct

Cursor's approach — procedural generation in Rust via `plant_geometries.rs`, with construction from parametric equations for each plant topology — is the right strategy. The minimum vertex counts from the Plant Catalogue are correctly reproduced. The threading requirement (geometry generation on background thread, GPU upload on main thread) is important and correctly identified.

### 1.5 The Single vs Nine Pipeline States Decision Is Correctly Scoped

Cursor correctly identifies this as a decision point rather than treating it as a blocker. One general shader with nine geometry sets is architecturally sufficient for the CERN demonstration. The 16.7 ms swap budget in PQ-UI-001 is achievable with geometry-only swaps — pipeline state switching is not the bottleneck. Nine separate pipeline states would enable plant-specific visual effects (pulsing ICF beamlines, glowing MIF gun positions) but are not required for physics-correct differentiation.

**Recommendation:** Ship with one pipeline state and nine geometries for CERN. File a P2 item for plant-specific shaders post-validation.

### 1.6 The 81-Swap UI Execution Gap Remains Correctly Identified

The existing `testPQCSE007_81SwapPermutationMatrix()` in `ControlSystemsProtocols.swift` uses API calls. The PQ-UI requirement is UI tab interactions. The XCTest UI automation approach is correct. This item belongs in PQ-UI and cannot be completed until the plant geometries exist and the FFI surface is extended.

---

## Part 2: The One Framing Error That Must Be Corrected

### 2.1 The WASM Module Is Not the Constitutional Safety Enforcement Layer

Cursor's revised plan reclassifies the WASM fix as **"P0 LIFE SAFETY"** and states that "without constitutional validation, plant could enter unsafe state."

This is incorrect. The WASM module runs inside a sandboxed JavaScript context inside a WKWebView. It does not have access to the Metal GPU, the NATS message bus, or the Rust UUM-8D engine core. It cannot halt the control loop, cannot issue REFUSED at the sovereignty layer, and cannot enforce the constitutional constraints that prevent unsafe plant states.

**The actual constitutional safety enforcement chain is in Rust:**

The thirty-two GxP OQ tests — the IQ, TP, TN, TR, TC, TI, and RG series — verify the Rust constitutional layer. The RG regression guard tests (RG-001 through RG-005) lock the ABI at the FFI boundary. The TI tests verify that NaN entropy and negative truth values are caught and clamped. The TN tests verify that malformed input never panics. Constitutional constraints C-001 through C-010 are enforced by the Rust crate at measurement ingestion time, before any NATS publication and long before any WKWebView dashboard receives data.

**What the WASM module actually is:** It is the human-readable display layer for constitutional state. It computes the dashboard-visible CALORIE/CURE/REFUSED verdict so the operator can read it in the browser context without a round-trip to the Rust engine for every frame. It is the most important element of the human interface. But it is not the safety enforcer.

**The corrected framing:**

| Component | Correct classification | Why |
| --- | --- | --- |
| Rust UUM-8D engine + 32 OQ tests | Constitutional safety enforcement | Runs before NATS publication, enforces C-001 through C-010, kills invalid measurements at source |
| WASM `constitutional_check()` | Operator visibility layer | Replicates constitutional logic in JS context for dashboard display; if WASM fails, the Rust layer still enforces |
| Vertex colour encoding (R=entropy, G=truth) | Real-time operator health signal | Operator sees process health via colour; WASM feeds the values that produce this signal |
| Nine plant wireframes | Regulatory visual compliance | A physicist must be able to visually identify each plant topology for the patent demonstration |
| PQ evidence chain (IQ/OQ/PQ receipts) | Regulatory acceptance | GxP documentary proof for CERN |

**The correct priority framing:**

- **P0:** WASM module (operator cannot see constitutional state without it — the dashboard is blind)
- **P0:** Vertex colour pipeline verification (end-to-end latency check of the real-time telemetry feed)
- **P1:** Nine plant wireframe geometries (regulatory visual differentiation — physicist must see a Tokamak not a cube)
- **P1:** FFI surface extension (Swift cannot drive geometry swaps without it)
- **P1:** PQ-UI test suite (12 tests, depends on WASM and geometry both being complete)
- **P2:** Pipeline state architecture decision (one vs nine shaders)
- **P2:** Seven domain selector confirmation

The priorities are the same. The reason for WASM being P0 changes: **it is not because WASM enforces safety, but because without WASM the operator cannot see safety state.** A control room where the operator cannot read the CALORIE/CURE/REFUSED badge is a safety risk not because the Rust layer stopped working, but because human oversight is lost.

---

## Part 3: What Is Still Missing from the Revised Plan

### 3.1 The FFI Extension Gap Is Underweighted

Cursor lists "Extend Rust FFI surface" as P1 item 5 — after WASM, after geometry generation. But the FFI extension is a prerequisite for testing plant geometry swaps from Swift. Without `gaia_metal_renderer_switch_plant()` in the C header, the Swift `WKScriptMessageHandler` that receives `switchPlant` messages cannot call into the Metal renderer.

**The correct dependency chain:**

```
Plant geometries (Rust) → FFI surface extension (C header + cbindgen) 
    → Swift integration update (RustMetalProxyRenderer.swift)
        → WKWebView plant selector UI can drive real geometry swaps
            → PQ-UI-001 plant swap timing test can run
                → 81-swap matrix through UI can execute
```

Geometry and FFI are co-equal P1 prerequisites. Neither is useful without the other. The plan should reflect this explicitly.

### 3.2 The Standalone Binary Architecture Still Not Addressed

The `gaia-metal-renderer` crate builds as both a `[[bin]]` target (standalone winit app via `main.rs`) and a `[lib]` target (C-callable FFI via `lib.rs`). The GaiaFusion Swift app uses the `[lib]` target. These two compilation targets currently have different capabilities: the `[bin]` target has the full `MetalRenderer` struct with `render_frame()` and `upload_geometry()`. The `[lib]` target only exposes `TauState`.

When Cursor writes the new FFI functions in `ffi.rs`, those functions need access to the `MetalRenderer` struct. The `MetalRenderer` needs a `CAMetalLayer`, which requires a window handle, which requires a running AppKit application. This means the FFI geometry upload functions can only work when called from within GaiaFusion's own AppKit context — which is the correct scenario, but it means the FFI cannot be tested in isolation on a CI server (Linux, no Metal).

The plan should explicitly state: **the new geometry FFI functions will be macOS-only and cannot be tested on the CI Linux runner.** The existing pattern in `renderer.rs` of marking expensive Metal-dependent code with `#[cfg(not(test))]` or `#[cfg(target_os = "macos")]` should be followed.

### 3.3 The Evidence Path Claim Needs Verification

Cursor's revised plan states: "Evidence path (subdirs vs flat) — Already Correct — IQ/OQ use subdirs, no fix needed. Confirmed by actual `ls evidence/`: `iq/`, `oq/`, `pq_composite/`, `pq_validation/` exist."

This cannot be confirmed from the GAIAFTCL repository. The GAIAFTCL `evidence/` directory contains four files, no subdirectories. If GaiaFusion's own `evidence/` directory uses subdirectories, that is a different repo and a different path. The IQ wiki document (`IQ-Installation-Qualification.md`) specifies the receipt as `evidence/iq_receipt.json` — flat, no subdirectory.

**The correct action:** When IQ is run on the CERN demonstration machine, verify which path `iq_install.sh` actually writes to. If the script writes to `evidence/iq/iq_receipt.json`, update the IQ wiki to match. If it writes to `evidence/iq_receipt.json`, update Cursor's validation scripts. The path should be consistent across: the `iq_install.sh` script output, the IQ wiki, the `oq_validate.sh` receipt reader, and any future `pq_validate.sh`. Do not assume it is already correct.

---

## Part 4: The Definitive Priority Register

This is the synthesised, corrected list. It supersedes both the original Cursor plan and the revised plan.

### P0 — Operator visibility (required for the dashboard to function at all)

| Item | Why P0 | Owner |
| --- | --- | --- |
| Build UUM-8D fusion WASM module (5 exports) | Dashboard blind without it — operator cannot read CALORIE/CURE/REFUSED | WASM team |
| Verify vertex colour pipeline end-to-end latency | Operator real-time health signal depends on this path being live | Integration |

### P1 — CERN demonstration (required for patent visual compliance)

| Item | Why P1 | Dependency |
| --- | --- | --- |
| Build 9 plant wireframe geometries in Rust | Physicist must see Tokamak, not cube | None |
| Extend Rust FFI (switch_plant, upload_geometry, render_frame) | Swift cannot drive Metal without this | Geometry exists |
| Regenerate C header (`cbindgen`), update Swift integration | FFI is not callable until header is regenerated | FFI functions written |
| Implement PQ-UI test suite (12 tests) | PQ compliance | WASM + Geometry + FFI |
| Write `scripts/pq_validate.sh` | PQ evidence collection | PQ-UI tests exist |
| Run IQ on CERN machine and confirm evidence path structure | GxP chain start | None (do now) |

### P2 — Quality and completeness

| Item | Why P2 |
| --- | --- |
| Resolve 1 vs 9 pipeline states architecture | Recommend 1 shader + 9 geometries for CERN; post-validation for visual effects |
| Confirm or implement 7-domain selector | Cross-domain requirement; not on the critical path for fusion demonstration |
| Vertex count assertions in plant swap tests | Compliance test; requires real geometries to mean anything |
| MIF Fibonacci gun placement lock test | Constitutional constraint C-009; specific to MIF |
| ICF n_e overflow path in WASM | PQ-UI-006; requires WASM to exist |

### P3 — Complete GxP chain

| Item |
| --- |
| Run OQ after every code change that touches vQbitPrimitive, GaiaVertex, or shaders (RG tests are the sentinel) |
| Run full PQ with real plant geometries (not cubes) |
| Collect τ-anchored PQ receipt for CERN submission |

---

## Part 5: The Correct "What CERN Sees" Summary

Cursor's "what CERN sees today vs when complete" section is accurate. The only addition:

**With WASM fixed but geometry still as cubes (intermediate state):**
- Terminal state badge: live and functional (CALORIE / CURE / REFUSED)
- vQbit entropy/truth plane: live and functional
- Closure residual bar: live and functional
- Metal viewport: nine differently-coloured cubes (telemetry-correct colours, wrong topology)
- A CERN physicist would say: "The constitutional validation works. The plant-specific visualisation is missing."

This intermediate state is demonstrable and has real value. It shows the UUM-8D engine working. It should be explicitly planned as a milestone checkpoint between WASM completion and geometry completion — not treated as a failure state.

---

## Consolidated Decision List for the Team

Three decisions are required before implementation can proceed. These cannot be resolved by the implementation team alone.

**Decision 1 — Geometry source strategy.** Procedural generation in Rust (parametric torus, cylinder, icosphere, geodesic) versus loading from canonical `.usda` files versus hand-crafted vertex arrays. Procedural generation is recommended: it is testable (vertex count assertions pass if the parametric equations are correct), it is sovereign (no external file dependency), and it is the approach Cursor correctly proposed.

**Decision 2 — Evidence path standard.** Run `iq_install.sh` on the CERN machine now, observe where it writes the receipt, and make that the canonical path for all scripts and all wiki documentation. Resolve the flat vs subdirectory ambiguity once and do not leave it as an open question across two repos.

**Decision 3 — CERN demo scope.** Explicitly list which of the "Should Have" requirements from Cursor's success criteria are in scope for the initial CERN validation and which are post-CERN. The seven-domain selector, in particular, is a significant implementation item that should either be confirmed as in scope now or explicitly deferred.

---

*CERN Plan Review v2 — GaiaFTCL Mac Cell*
*FortressAI Research Institute | Norwich, Connecticut*
*Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie*
