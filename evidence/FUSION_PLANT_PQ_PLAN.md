# GaiaFusion Plant Control System — Performance Qualification Plan
**Document:** GFTCL-PQ-002  
**Revision:** 1.0 DRAFT  
**Framework:** GAMP 5 (EU Annex 11) + FDA 21 CFR Part 11  
**Facility:** CERN Research Campus  
**Date:** 2026-04-13  
**Status:** CONFIDENTIAL — GxP Controlled Document

---

## Signatures

| Role | Name | Signature | Date |
|---|---|---|---|
| Author (SW QA) | | | |
| Reviewer (Physics) | | | |
| Reviewer (Control Systems) | | | |
| Approver (Safety / RP) | | | |
| QA Release | | | |

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [System Description](#2-system-description)
3. [The Nine Canonical Plant Types](#3-the-nine-canonical-plant-types)
4. [Physics Invariants Per Plant](#4-physics-invariants-per-plant)
5. [Plant Swap Lifecycle](#5-plant-swap-lifecycle)
6. [Epistemic Classification System](#6-epistemic-classification-system)
7. [PQ Test Protocols — Physics Team (PQ-PHY)](#7-pq-test-protocols--physics-team-pq-phy)
8. [PQ Test Protocols — Control Systems Engineering (PQ-CSE)](#8-pq-test-protocols--control-systems-engineering-pq-cse)
9. [PQ Test Protocols — Software QA (PQ-QA)](#9-pq-test-protocols--software-qa-pq-qa)
10. [PQ Test Protocols — Safety Team (PQ-SAF)](#10-pq-test-protocols--safety-team-pq-saf)
11. [Configuration Management](#11-configuration-management)
12. [Evidence Requirements](#12-evidence-requirements)
13. [Deliverables Checklist](#13-deliverables-checklist)
14. [Execution Schedule and Sign-Off](#14-execution-schedule-and-sign-off)

---

## 1. Purpose and Scope

### 1.1 Purpose

This Performance Qualification Plan defines the tests, acceptance criteria, evidence requirements, and team responsibilities required to demonstrate that the GaiaFusion Plant Control System performs within its specified physical parameters under real operational conditions at CERN.

PQ validates three categories of system behaviour:

- **Physics fidelity** — telemetry values (I_p, B_T, n_e) stay within plant-specific operational windows and map correctly to the Metal renderer colour channels
- **Plant swap integrity** — all nine plant types load, render, and transition through the defined lifecycle without entering REFUSED terminal state
- **Epistemic boundary preservation** — M/T/I/A classification tags survive plant swaps and renderer updates unchanged

### 1.2 Scope

| Component | Files | PQ Coverage |
|---|---|---|
| Plant kinds catalogue | `PlantKindsCatalog.swift` | All 9 plant types, geometry vertex counts |
| Wireframe geometry | `FusionFacilityWireframeGeometry.swift` | Per-plant wireframe element validation |
| Telemetry ring | `OpenUSDPlaybackRing.swift` | I_p / B_T / n_e bounds, M/T/I/A tags |
| Swap state machine | `SwapState.swift` | Full lifecycle, all terminal states |
| Metal renderer | `renderer.rs` (Rust) | Frame integrity, colour mapping, timing |
| Plant USD resources | `Resources/usd/plants/` | All 9 timeline_v2.json configs |
| WASM bridge | WASM telemetry inputs | Data flow from bridge to playback ring |

### 1.3 Out of Scope

NATS mesh qualification, SSH tunnel security, WKWebView shell, host OS qualification, and network infrastructure are addressed in separate protocols.

---

## 2. System Description

### 2.1 Architecture

```
WASM Bridge ──[I_p, B_T, n_e]──► OpenUSDPlaybackRing ──[M/T/I/A tags]──► Rust Metal Renderer ──► CAMetalLayer
                                         │
                                         └──[terminal state]──► UI Controls
                                                                    ├── CALORIE → normal render
                                                                    ├── CURE    → degraded render
                                                                    └── REFUSED → red error tint
```

### 2.2 Telemetry Channels

| Channel | Physical Quantity | Units | Colour Mapping |
|---|---|---|---|
| I_p | Plasma current | MA (megaamperes) | Blue channel |
| B_T | Toroidal magnetic field | T (tesla) | Green channel |
| n_e | Electron density | m⁻³ | Red channel |

All three channels animate over time. The Metal renderer maps normalised telemetry values to RGB colour gradient on the wireframe topology.

### 2.3 Terminal States

| State | Meaning | Renderer Behaviour | Action Required |
|---|---|---|---|
| CALORIE | Swap complete, full operation | Normal colour gradient | None |
| CURE | Swap complete, degraded operation | Normal render, degraded telemetry | Alert operator, log deviation |
| REFUSED | Invalid plant or mesh loss | Red error tint | Halt, root cause analysis, NCR |

---

## 3. The Nine Canonical Plant Types

Each plant type has a defined wireframe topology. PQ must verify geometry is non-empty and physically consistent for all nine.

| Plant ID | Physics Name | Confinement Approach | Key Wireframe Elements |
|---|---|---|---|
| `tokamak` | Axisymmetric toroidal confinement | External TF + PF coils | Nested torus + PF coil stack + D-shaped TF loops |
| `stellarator` | 3D twisted torus, no plasma current | Twisted external coils only | Twisted vessel + modular coil windings |
| `spherical_tokamak` | Low aspect ratio, cored sphere | Dense central solenoid | Cored sphere + dense solenoid + asymmetric TF |
| `frc` | Field-Reversed Configuration | Linear, no TF | Cylinder + end formation coils + confinement rings |
| `mirror` | Open magnetic mirror | End choke coils | Sparse central rings + dense end choke coils |
| `spheromak` | Self-organized compact torus | Coaxial injector | Spherical flux conserver + coaxial injector |
| `z_pinch` | Pure pinch, no external TF | Electrode plates | Cylinder + electrode plates + spokes |
| `mif` | Magneto-Inertial Fusion | Plasma jet merger | Icosphere + radial plasma guns (Fibonacci sites) |
| `inertial` | ICF, laser-driven implosion | Inward beamlines | Geodesic shell + hohlraum + inward beamlines |

---

## 4. Physics Invariants Per Plant

### 4.1 Invariant Definition

Each plant defines a valid operational window for each telemetry channel. **Values outside these windows constitute a plant invariant violation** — a critical failure requiring halt and NCR. Values at NaN or Inf are unconditional critical failures regardless of plant type.

### 4.2 Per-Plant Telemetry Bounds

#### Tokamak (NSTX-U baseline)

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 0.85 | 0.50 | 2.00 | MA | Measured (M) |
| B_T | 0.52 | 0.40 | 1.00 | T | Measured (M) |
| n_e | 3.5×10¹⁹ | 1×10¹⁹ | 1×10²⁰ | m⁻³ | Measured (M) |

Physical constraints:
- I_p > 0.5 MA required for ohmic heating
- B_T > 0.4 T required for confinement
- n_e in [1×10¹⁹, 1×10²⁰] m⁻³ is operational window (below = too thin, above = disruption risk)

#### Stellarator

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 0.00 | 0.00 | 0.05 | MA | Tested (T) |
| B_T | 2.50 | 1.50 | 3.50 | T | Measured (M) |
| n_e | 2.0×10¹⁹ | 5×10¹⁸ | 5×10¹⁹ | m⁻³ | Tested (T) |

Note: Stellarators operate with near-zero plasma current. I_p > 0.05 MA indicates configuration error.

#### Spherical Tokamak

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 1.20 | 0.80 | 2.50 | MA | Measured (M) |
| B_T | 0.30 | 0.20 | 0.60 | T | Measured (M) |
| n_e | 5.0×10¹⁹ | 2×10¹⁹ | 2×10²⁰ | m⁻³ | Measured (M) |

Note: Low aspect ratio allows lower B_T than conventional tokamak.

#### Field-Reversed Configuration (FRC)

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 0.10 | 0.01 | 0.50 | MA | Tested (T) |
| B_T | 0.00 | 0.00 | 0.10 | T | Tested (T) |
| n_e | 1.0×10²¹ | 1×10²⁰ | 1×10²² | m⁻³ | Inferred (I) |

Note: FRC is a field-reversed configuration — no significant toroidal field. Very high density operation.

#### Mirror

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 0.05 | 0.00 | 0.20 | MA | Tested (T) |
| B_T | 1.00 | 0.50 | 3.00 | T | Measured (M) |
| n_e | 5.0×10¹⁸ | 1×10¹⁸ | 1×10¹⁹ | m⁻³ | Inferred (I) |

Note: Open-ended configuration — lower density than closed confinement.

#### Spheromak

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 0.30 | 0.10 | 0.80 | MA | Tested (T) |
| B_T | 0.10 | 0.05 | 0.30 | T | Inferred (I) |
| n_e | 1.0×10²⁰ | 1×10¹⁹ | 1×10²¹ | m⁻³ | Inferred (I) |

#### Z-Pinch

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 2.00 | 0.50 | 20.0 | MA | Measured (M) |
| B_T | 0.00 | 0.00 | 0.05 | T | Tested (T) |
| n_e | 1.0×10²² | 1×10²¹ | 1×10²³ | m⁻³ | Inferred (I) |

Note: Z-pinch requires very high plasma current. B_T ~ 0 by definition.

#### Magneto-Inertial Fusion (MIF)

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 0.50 | 0.10 | 5.00 | MA | Tested (T) |
| B_T | 0.50 | 0.10 | 2.00 | T | Inferred (I) |
| n_e | 1.0×10²³ | 1×10²² | 1×10²⁵ | m⁻³ | Assumed (A) |

Note: MIF targets ignition-relevant densities. n_e bounds are assumed from target design.

#### Inertial Confinement Fusion (ICF)

| Parameter | Baseline | Min | Max | Unit | Epistemic |
|---|---|---|---|---|---|
| I_p | 0.00 | 0.00 | 0.01 | MA | Assumed (A) |
| B_T | 0.00 | 0.00 | 0.01 | T | Assumed (A) |
| n_e | 1.0×10³¹ | 1×10³⁰ | 1×10³² | m⁻³ | Assumed (A) |

Note: ICF uses laser drivers, not magnetic confinement. Plasma current and toroidal field are effectively zero. Electron density at ignition is extreme.

### 4.3 Cross-Plant Invariant Rules

These rules apply regardless of plant type:

1. **NaN/Inf prohibition** — Any NaN or Inf in I_p, B_T, or n_e is an unconditional critical failure
2. **Negative prohibition** — I_p, B_T, and n_e must be ≥ 0.0 for all plants
3. **Colour channel normalisation** — All three values must be normalisable to [0.0, 1.0] for Metal renderer colour mapping. Values must be clamped only for display; raw telemetry must be logged with actual values
4. **Epistemic tag preservation** — M/T/I/A tags must not change during a render frame or plant swap

---

## 5. Plant Swap Lifecycle

### 5.1 State Machine

```
[*] ──► REQUESTED ──► DRAINING ──► COMMITTED ──► VERIFIED ──► [*]
                                                      │
                                         ┌────────────┼─────────────┐
                                      CALORIE       CURE        REFUSED
                                    (success)   (degraded)    (failure)
```

### 5.2 State Definitions

| State | Entry Condition | Exit Condition | Maximum Duration |
|---|---|---|---|
| REQUESTED | User activates SWAP MATRIX | Telemetry ramp-down begins | 500 ms |
| DRAINING | Ramp-down initiated | New plant USD loaded | 2000 ms |
| COMMITTED | New plant USD loaded | First frame rendered and validated | 1000 ms |
| VERIFIED | First frame complete | Terminal state assigned | 200 ms |
| CALORIE | Verification passes all checks | Swap protocol complete | — |
| CURE | Verification passes with degraded telemetry | Operator alerted | — |
| REFUSED | Mesh loss or invalid plant | Error tint active, NCR opened | — |

### 5.3 REFUSED Conditions

A swap MUST enter REFUSED (not silently continue) if any of the following occur:
- Loaded plant USD produces zero vertices
- Any telemetry value is NaN or Inf after plant load
- Metal renderer reports GPU error on first frame
- Plant ID not in the nine canonical types

### 5.4 Full Permutation Matrix

PQ requires every plant-to-plant swap be tested. 9×9 = 81 transitions (72 cross-plant + 9 same-plant reload).

| From \ To | tokamak | stellarator | spherical_tokamak | frc | mirror | spheromak | z_pinch | mif | inertial |
|---|---|---|---|---|---|---|---|---|---|
| tokamak | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| stellarator | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| spherical_tokamak | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| frc | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| mirror | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| spheromak | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| z_pinch | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| mif | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| inertial | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

---

## 6. Epistemic Classification System

### 6.1 Classification Definitions

| Tag | Name | Definition | Example |
|---|---|---|---|
| M | Measured | Value derived from direct experimental measurement at an operating facility | NSTX-U I_p = 0.85 MA from shot data |
| T | Tested | Value derived from validated simulation or laboratory test | Stellarator B_T from W7-X design studies |
| I | Inferred | Value derived from physical scaling laws or extrapolation from related measurements | FRC n_e from liner compression models |
| A | Assumed | Value assumed from target design parameters or theoretical prediction | ICF n_e at ignition from NIF hohlraum models |

### 6.2 Epistemic Invariants

1. Tags must be assigned per-channel per-plant in `timeline_v2.json`
2. Tags must be read-only at runtime — no runtime modification permitted
3. Tags must survive plant swaps unchanged (the tag belongs to the plant definition, not the renderer state)
4. Downgrade prohibited — a channel tagged M may not be re-tagged I or A without a Change Control Record

---

## 7. PQ Test Protocols — Physics Team (PQ-PHY)

**Prerequisite:** IQ and OQ complete. All 32 automated Rust tests passing. Reference dataset certified and hash-locked.  
**Authority:** Physics Lead (PhD required) + independent co-sign for invariant verification.

### PQ-PHY-001: Tokamak Telemetry Bounds Verification

| Field | Detail |
|---|---|
| Invariant | I_p ∈ [0.5, 2.0] MA, B_T ∈ [0.4, 1.0] T, n_e ∈ [1e19, 1e20] m⁻³ |
| Procedure | Load tokamak plant. Run 120 frames. Sample I_p, B_T, n_e every 10 frames. Assert all values within bounds. Assert no NaN/Inf. |
| Acceptance | 100% samples in range. Zero NaN/Inf. |
| Evidence | `tokamak_telemetry_log.csv`, Physics Lead signature |

### PQ-PHY-002: Stellarator Zero-Current Constraint

| Field | Detail |
|---|---|
| Invariant | I_p ≤ 0.05 MA at all times |
| Procedure | Load stellarator plant. Run 300 frames. Verify I_p never exceeds 0.05 MA. |
| Acceptance | Max(I_p) ≤ 0.05 MA across all frames. |
| Evidence | `stellarator_telemetry_log.csv`, Physics Lead signature |

### PQ-PHY-003: All Nine Plants Telemetry Bounds

| Field | Detail |
|---|---|
| Invariant | Per-plant bounds table (Section 4.2) |
| Procedure | For each of the 9 plants: load plant, run 120 frames, sample all three telemetry channels every 10 frames, assert within plant-specific bounds. |
| Acceptance | 100% in-bounds for all 9 plants × 3 channels. Zero NaN/Inf across all 9. |
| Evidence | `all_plants_telemetry_log.csv` with per-plant rows, Physics Lead signature |

### PQ-PHY-004: Epistemic Tag Correctness Per Plant

| Field | Detail |
|---|---|
| Invariant | M/T/I/A tags match Section 4.2 table for each plant |
| Procedure | For each plant: load, read M/T/I/A tags for I_p, B_T, n_e. Assert match against certified reference table. |
| Acceptance | All 27 tag assertions pass (9 plants × 3 channels). |
| Evidence | `epistemic_tag_verification.json` |

### PQ-PHY-005: Epistemic Tag Preservation Across Swap

| Field | Detail |
|---|---|
| Invariant | M/T/I/A tags unchanged before and after any plant swap |
| Procedure | Record all tags for plant A. Execute swap to plant B. Record all tags. Swap back to plant A. Assert tags match original. Repeat for 5 different swap pairs. |
| Acceptance | Zero tag mutations across all 5 swap pairs tested. |
| Evidence | Pre/post swap tag comparison log, Physics Lead signature |

### PQ-PHY-006: ICF/MIF High-Density Normalisation

| Field | Detail |
|---|---|
| Invariant | n_e values at 10³¹ m⁻³ (ICF) must normalise to [0,1] for renderer without overflow |
| Procedure | Load ICF plant. Assert renderer colour red channel is in [0.0, 1.0] f32. Assert no Inf in normalised value. |
| Acceptance | Normalised n_e ∈ [0.0, 1.0]. No overflow. |
| Evidence | `icf_normalisation_log.json` |

### PQ-PHY-007: Negative Value Prohibition

| Field | Detail |
|---|---|
| Invariant | I_p, B_T, n_e ≥ 0.0 for all plants at all times |
| Procedure | Monitor all three channels for all 9 plants over 120 frames each. Assert no negative values. |
| Acceptance | Zero negative values recorded. |
| Evidence | `negative_value_scan.csv` |

### PQ-PHY-008: NaN/Inf Injection Response

| Field | Detail |
|---|---|
| Invariant | System must halt and alert on NaN/Inf — not silently continue |
| Procedure | Inject NaN into I_p for tokamak plant. Verify system enters REFUSED and displays red error tint within 100 ms. Open NCR. |
| Acceptance | REFUSED state within 100 ms. Red tint active. NCR created. Normal processing stopped. |
| Evidence | `nan_injection_response_log.json`, Safety Officer co-sign |

---

## 8. PQ Test Protocols — Control Systems Engineering (PQ-CSE)

**Prerequisite:** PQ-PHY complete and signed.  
**Authority:** Senior CSE Engineer. Interlock tests require Safety Team co-sign.

### PQ-CSE-001: All Nine Plants Load Non-Zero Geometry

| Field | Detail |
|---|---|
| Invariant | INV-003 — every plant wireframe has vertex_count > 0 |
| Procedure | For each of 9 plants: load plant USD, query vertex buffer, assert count > 0, assert no Metal GPU errors. |
| Acceptance | All 9 plants return vertex_count > 0. Zero Metal errors. |
| Evidence | `plant_geometry_counts.json` (9 rows, vertex count per plant) |

### PQ-CSE-002: Wireframe Element Counts Per Plant

| Plant | Min Vertices | Min Indices | Rationale |
|---|---|---|---|
| tokamak | 48 | 96 | Torus + PF stack + TF loops |
| stellarator | 48 | 96 | Twisted vessel + modular coils |
| spherical_tokamak | 32 | 64 | Cored sphere + solenoid |
| frc | 24 | 48 | Cylinder + end coils |
| mirror | 24 | 48 | Rings + end choke coils |
| spheromak | 32 | 64 | Flux conserver + injector |
| z_pinch | 16 | 32 | Cylinder + electrodes |
| mif | 40 | 80 | Icosphere + Fibonacci guns |
| inertial | 40 | 80 | Geodesic shell + beamlines |

**Acceptance:** All plants meet or exceed minimum counts.

### PQ-CSE-003: Continuous Render 300 Seconds — All Plants

| Field | Detail |
|---|---|
| Invariant | INV-003 — frame drop < 0.1% over any 60-second window |
| Procedure | For each of 9 plants: run render loop 300 seconds. Collect frame count, drop count. Assert drop rate < 0.1%. |
| Acceptance | All 9 plants < 0.1% drop rate over 300 s. |
| Evidence | `continuous_render_metrics.csv` (9 rows) |

### PQ-CSE-004: Plant Swap Latency

| Field | Detail |
|---|---|
| Invariant | REQUESTED → VERIFIED lifecycle must complete in ≤ 3700 ms (sum of state maximums) |
| Procedure | Execute 20 random plant swaps. Time each from REQUESTED to terminal state. Assert all ≤ 3700 ms. |
| Acceptance | All 20 swaps complete ≤ 3700 ms. Zero REFUSED on valid plants. |
| Evidence | `swap_latency_log.csv` |

### PQ-CSE-005: Full 81-Swap Permutation Matrix

| Field | Detail |
|---|---|
| Invariant | All 9×9 plant-to-plant swap combinations must reach CALORIE or CURE (never REFUSED) |
| Procedure | Execute all 81 swap combinations from Section 5.4. Record terminal state for each. |
| Acceptance | Zero REFUSED states. All 81 swaps reach CALORIE or CURE. |
| Evidence | `swap_permutation_matrix.json` (81 entries) |

### PQ-CSE-006: REFUSED on Invalid Plant Detected

| Field | Detail |
|---|---|
| Invariant | Swap to invalid/unknown plant must enter REFUSED, not silent failure |
| Procedure | Attempt swap to plant_id = "unknown". Assert REFUSED within 500 ms. Assert red tint active. |
| Acceptance | REFUSED state and red tint within 500 ms. |
| Evidence | `refused_invalid_plant_log.json` |

### PQ-CSE-007: REFUSED on Mesh Loss

| Field | Detail |
|---|---|
| Invariant | Zero-vertex geometry must trigger REFUSED |
| Procedure | Load plant USD that produces zero vertices. Assert REFUSED entered. |
| Acceptance | REFUSED on zero-vertex geometry. |
| Evidence | `refused_mesh_loss_log.json` |

### PQ-CSE-008: Telemetry Colour Gradient Validation

| Field | Detail |
|---|---|
| Invariant | I_p → blue, B_T → green, n_e → red, all channels ∈ [0.0, 1.0] after normalisation |
| Procedure | Set known telemetry values. Sample rendered pixel colours from Metal layer. Assert channel mapping correct within ±0.02. |
| Acceptance | All three channel mappings correct for 5 test value sets across 3 plants. |
| Evidence | `colour_mapping_validation.json` |

### PQ-CSE-009 through PQ-CSE-012

| ID | Title | Invariant | Acceptance |
|---|---|---|---|
| PQ-CSE-009 | Control loop jitter < 1 ms over 1000 cycles | INV-004 | Max jitter < 1 ms |
| PQ-CSE-010 | End-to-end latency WASM → renderer < 5 ms | INV-004 | P99 < 5 ms |
| PQ-CSE-011 | Vertex ABI stride 28 bytes on CERN hardware | INV-003 | Exact match CI results |
| PQ-CSE-012 | Uniforms ABI stride 64 bytes on CERN hardware | INV-003 | Exact match CI results |

---

## 9. PQ Test Protocols — Software QA (PQ-QA)

**Prerequisite:** PQ-PHY and PQ-CSE complete and signed.  
**Authority:** QA Manager.

### PQ-QA-001: Automated Full Cycle Receipt

| Field | Detail |
|---|---|
| Procedure | Execute: `zsh scripts/run_full_cycle.sh`. All 5 phases must complete green. |
| Acceptance | 32 Rust tests passed. `full_cycle_receipt.json` status = FULL_CYCLE_GREEN. GitHub Actions green. |
| Evidence | `evidence/full_cycle_receipt.json`, GitHub Actions run URL |

### PQ-QA-002: Swift Continuous Operation Test Suite

| Field | Detail |
|---|---|
| Procedure | Execute `swift test --filter PlantContinuousOperationTests`. All test methods must pass. |
| Test methods | `testAllNinePlantsLoadAndRenderContinuously`, `testPlantSwapCycleAllToAll`, `testTelemetryEpistemicBoundary` |
| Acceptance | All Swift tests PASS. Zero REFUSED states. |
| Evidence | `swift_test_output.txt` |

### PQ-QA-003: Evidence Generation Script

| Field | Detail |
|---|---|
| Procedure | Execute `zsh scripts/generate_pq_evidence.sh`. Verify all 9 plant screenshots captured. Verify telemetry JSON written. |
| Acceptance | 9 screenshot files in `evidence/pq_validation/screenshots/`. `PLANT_PQ_EVIDENCE_<timestamp>.json` written with all 9 plants present. |
| Evidence | `PLANT_PQ_EVIDENCE_<timestamp>.json` |

### PQ-QA-004 through PQ-QA-010

| ID | Title | Acceptance |
|---|---|---|
| PQ-QA-004 | Build reproducibility — two clean builds SHA256 identical | Binary SHA256 matches |
| PQ-QA-005 | No target/ in git history | `git log --all -- '**/target/**'` returns zero results |
| PQ-QA-006 | Cargo.lock committed and matches | Zero uncommitted changes |
| PQ-QA-007 | Binary size < 5 MB (zero OpenUSD bloat) | `du -h` < 5 MB |
| PQ-QA-008 | Instruments: zero memory leaks over 60 s | 0 leaked bytes |
| PQ-QA-009 | timeline_v2.json present for all 9 plants | 9 files found in Resources/usd/plants/ |
| PQ-QA-010 | Electronic records audit trail — no force-push after PQ | Git log shows linear history |

---

## 10. PQ Test Protocols — Safety Team (PQ-SAF)

**Prerequisite:** All previous PQ phases signed. Safety Officer physically present for all SAF tests.  
**Authority:** Safety Officer (independent of development team) + CERN Radiation Protection.

### PQ-SAF-001: Invariant Breach — REFUSED and Halt

| Field | Detail |
|---|---|
| Objective | Out-of-range telemetry triggers REFUSED and halts processing. Not a silent clamp. |
| Procedure | Inject I_p = 999 MA into tokamak plant (above max of 2.0 MA). Verify REFUSED within 100 ms. Verify red tint. Verify processing halted. NCR opened. |
| Acceptance | REFUSED ≤ 100 ms. Red tint active. Processing halted. NCR auto-created. |
| Evidence | Alert log, halt confirmation, NCR reference, Safety Officer signature |

### PQ-SAF-002 through PQ-SAF-008

| ID | Title | Witness Required | Acceptance |
|---|---|---|---|
| PQ-SAF-002 | NaN injection → REFUSED across all 3 channels | Safety Officer | REFUSED ≤ 100 ms per channel |
| PQ-SAF-003 | Negative I_p injection → REFUSED | Safety Officer | REFUSED ≤ 100 ms |
| PQ-SAF-004 | CURE state degraded telemetry alert | Safety Officer | Operator alert issued within 500 ms |
| PQ-SAF-005 | Emergency stop halts control loop | Safety Officer + RP | Loop halts ≤ 50 ms |
| PQ-SAF-006 | Process crash → defined safe state | Safety Officer | Safe state entered, no undefined behaviour |
| PQ-SAF-007 | REFUSED NCR workflow completion | QA Manager co-sign | NCR created, routed, closed |
| PQ-SAF-008 | Radiation interlock compatibility | RP Team | System responds per RP SOP |

---

## 11. Configuration Management

### 11.1 Controlled Configuration Items

| CI ID | Item | Change Triggers |
|---|---|---|
| CI-001 | Per-plant telemetry bounds (Section 4.2) | Full PQ-PHY re-execution |
| CI-002 | M/T/I/A tag assignments per plant | PQ-PHY-004 and PQ-PHY-005 re-execution |
| CI-003 | Plant swap state machine transitions and timeouts | Full PQ-CSE re-execution |
| CI-004 | Terminal state definitions (CALORIE/CURE/REFUSED) | PQ-CSE + PQ-SAF re-execution |
| CI-005 | Nine canonical plant IDs and wireframe geometry | PQ-CSE-001, PQ-CSE-002 re-execution |
| CI-006 | Telemetry channel→colour mapping (I_p=B, B_T=G, n_e=R) | PQ-CSE-008 re-execution |
| CI-007 | vQbitPrimitive ABI (size 76 bytes, field offsets) | Full PQ re-execution |
| CI-008 | Rust toolchain version | PQ-QA-001, PQ-QA-004 re-execution |
| CI-009 | timeline_v2.json format and field names | PQ-PHY-003 + PQ-QA-009 re-execution |
| CI-010 | Target hardware platform | PQ-CSE full re-execution |

### 11.2 Prohibited Changes Without CCR

- Any change to telemetry bounds in Section 4.2
- Any change to the REFUSED trigger conditions
- Any downgrade of M/T/I/A tags
- Removal of any of the nine canonical plant types
- Any `git push --force` after PQ evidence collection begins

---

## 12. Evidence Requirements

### 12.1 Mandatory Evidence Artifacts

| Artifact | Source | Format | Retention |
|---|---|---|---|
| `full_cycle_receipt.json` | `run_full_cycle.sh` | JSON, schema GFTCL-TEST-RUST-001 | 10 years minimum |
| `PLANT_PQ_EVIDENCE_<ts>.json` | `generate_pq_evidence.sh` | JSON, 9 plant entries | 10 years minimum |
| `all_plants_telemetry_log.csv` | Physics Team | CSV, 9 plants × 3 channels | 10 years minimum |
| `swap_permutation_matrix.json` | CSE Team | JSON, 81 entries | 10 years minimum |
| `plant_geometry_counts.json` | CSE Team | JSON, 9 rows | 10 years minimum |
| Per-plant screenshots (9 files) | `generate_pq_evidence.sh` | PNG | 10 years minimum |
| `swift_test_output.txt` | `swift test` | Plain text, timestamped | 10 years minimum |
| Physics Invariant Verification Report | Physics Lead | Signed PDF or DOCX | 10 years minimum |
| Safety Officer witness records | Safety Team | Wet or electronic signature | 10 years minimum |
| GitHub Actions run URL + artifact | CI | URL + downloaded ZIP | Permanent |
| Git commit SHA (PQ baseline) | `git rev-parse HEAD` | 40-char SHA | Permanent (git history) |

### 12.2 Evidence Directory Structure

```
evidence/
├── full_cycle_receipt.json
└── pq_validation/
    ├── PLANT_PQ_EVIDENCE_<timestamp>.json
    ├── screenshots/
    │   ├── tokamak_<timestamp>.png
    │   ├── stellarator_<timestamp>.png
    │   ├── spherical_tokamak_<timestamp>.png
    │   ├── frc_<timestamp>.png
    │   ├── mirror_<timestamp>.png
    │   ├── spheromak_<timestamp>.png
    │   ├── z_pinch_<timestamp>.png
    │   ├── mif_<timestamp>.png
    │   └── inertial_<timestamp>.png
    ├── telemetry/
    │   ├── all_plants_telemetry_log.csv
    │   ├── epistemic_tag_verification.json
    │   └── nan_injection_response_log.json
    ├── swap/
    │   ├── swap_permutation_matrix.json
    │   └── swap_latency_log.csv
    ├── geometry/
    │   └── plant_geometry_counts.json
    └── receipts/
        ├── PQ_VALIDATION_REPORT.md
        └── final_receipt.json
```

---

## 13. Deliverables Checklist

| # | Deliverable | File | Owner | Status |
|---|---|---|---|---|
| 1 | Operator's Guide | `docs/FUSION_OPERATOR_GUIDE.md` | SW QA | ☐ |
| 2 | Physics Invariants Reference | `docs/PLANT_INVARIANTS.md` | Physics Team | ☐ |
| 3 | Continuous Operation Test Suite | `Tests/PlantContinuousOperationTests.swift` | SW QA | ☐ |
| 4 | Evidence Generation Script | `scripts/generate_pq_evidence.sh` | SW QA | ☐ |
| 5 | PQ Validation Report | `evidence/pq_validation/PQ_VALIDATION_REPORT.md` | QA Manager | ☐ |
| 6 | Full Cycle Receipt (automated) | `evidence/full_cycle_receipt.json` | CI / SW QA | ☐ |
| 7 | Physics Invariant Verification Report | PDF, signed | Physics Lead | ☐ |
| 8 | Safety Officer Witness Records | PDF, signed | Safety Officer | ☐ |
| 9 | This PQ Plan, completed and signed | `evidence/GFTCL-PQ-002_signed.docx` | QA Manager | ☐ |

---

## 14. Execution Schedule and Sign-Off

### 14.1 Phase Sequence

| Phase | Tests | Team Lead | Prerequisite | Est. Duration |
|---|---|---|---|---|
| 0 | IQ + OQ complete. 32 Rust tests green. CI green. | SW QA | None | 1 day |
| 1 | PQ-PHY-001 to PQ-PHY-008 | Physics Lead | Phase 0 signed | 2 days |
| 2 | PQ-CSE-001 to PQ-CSE-012 | CSE Lead | Phase 1 signed | 3 days |
| 3 | PQ-QA-001 to PQ-QA-010 | QA Manager | Phase 2 signed | 2 days |
| 4 | PQ-SAF-001 to PQ-SAF-008 | Safety Officer | Phase 3 signed | 2 days |
| 5 | Final review + QA release | QA Manager | Phase 4 signed, 0 open deviations | 1 day |

**Total estimated duration: 11 working days**

### 14.2 Phase Sign-Off

| Phase | Tests Executed | Pass / Fail | Signed By | Date |
|---|---|---|---|---|
| Physics | PQ-PHY-001 to PQ-PHY-008 | | | |
| CSE | PQ-CSE-001 to PQ-CSE-012 | | | |
| SW QA | PQ-QA-001 to PQ-QA-010 | | | |
| Safety | PQ-SAF-001 to PQ-SAF-008 | | | |
| QA Release | All phases | | | |

### 14.3 Final Release Statement

I confirm all PQ phases complete, all acceptance criteria met, all deviations resolved, and all evidence archived. The GaiaFusion Plant Control System is hereby released for production operation at CERN.

**QA Manager:** ________________________________ **Date:** ________________

---

*END OF DOCUMENT — GFTCL-PQ-002 Rev 1.0*  
*GaiaFusion Plant Control System — Performance Qualification Plan*  
*GAMP 5 | EU Annex 11 | FDA 21 CFR Part 11 | CERN Research Facility*
