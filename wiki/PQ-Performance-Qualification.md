# PQ — Performance Qualification

Performance Qualification proves that the system performs within its specified physical parameters under real operational conditions. PQ is executed after IQ and OQ are complete and signed.

**Document reference:** GFTCL-PQ-002
**Framework:** GAMP 5 | EU Annex 11 | FDA 21 CFR Part 11 | CERN Research Facility
**Prerequisite:** IQ signed. OQ passing (32/32 tests). All regression guards green.

---

## PQ Teams and Authority

| Phase | Team | Lead authority | Prerequisite |
| --- | --- | --- | --- |
| PQ-PHY | Physics Team | Physics Lead (PhD required) | IQ + OQ signed |
| PQ-CSE | Control Systems Engineering | Senior CSE Engineer | PQ-PHY signed |
| PQ-QA | Software QA | QA Manager | PQ-CSE signed |
| PQ-SAF | Safety | Safety Officer (independent) | PQ-QA signed |

Interlock tests (PQ-SAF) require the Safety Officer to be **physically present**.

---

## Plant Swap State Machine

All nine plant kinds share the same swap lifecycle.

```
[*] ──► REQUESTED ──► DRAINING ──► COMMITTED ──► VERIFIED ──► [*]
                                                      │
                                         ┌────────────┼─────────────┐
                                      CALORIE       CURE        REFUSED
                                    (success)   (degraded)    (failure)
```

| State | Maximum duration | Entry condition | Exit condition |
| --- | --- | --- | --- |
| REQUESTED | 500 ms | User activates SWAP MATRIX | Telemetry ramp-down begins |
| DRAINING | 2000 ms | Ramp-down initiated | New plant USD loaded |
| COMMITTED | 1000 ms | New plant USD loaded | First frame rendered and validated |
| VERIFIED | 200 ms | First frame complete | Terminal state assigned |
| CALORIE | — | All checks pass | Swap complete, normal operation |
| CURE | — | Checks pass with degraded telemetry | Operator alerted, log deviation |
| REFUSED | — | Mesh loss, invalid plant, or NaN/Inf | Red error tint active, NCR opened |

REFUSED is never silent. Any of the following **must** trigger REFUSED:
- Loaded plant USD produces zero vertices
- Any telemetry value is NaN or Inf after plant load
- Metal renderer reports GPU error on first frame
- Plant ID not in the nine canonical kinds

---

## PQ-PHY — Physics Team Protocols

### PQ-PHY-001: Tokamak Telemetry Bounds

| | |
| --- | --- |
| **Invariant** | I_p ∈ [0.5, 2.0] MA · B_T ∈ [0.4, 1.0] T · n_e ∈ [1×10¹⁹, 1×10²⁰] m⁻³ |
| **Procedure** | Load tokamak plant. Run 120 frames. Sample I_p, B_T, n_e every 10 frames. Assert all values within bounds. Assert no NaN/Inf. |
| **Acceptance** | 100% of samples in range. Zero NaN/Inf. |
| **Evidence** | `telemetry/tokamak_telemetry_log.csv` · Physics Lead signature |

### PQ-PHY-002: Stellarator Zero-Current Constraint

| | |
| --- | --- |
| **Invariant** | I_p ≤ 0.05 MA at all times |
| **Procedure** | Load stellarator plant. Run 300 frames. Verify I_p never exceeds 0.05 MA. |
| **Acceptance** | Max(I_p) ≤ 0.05 MA across all frames. |
| **Evidence** | `telemetry/stellarator_telemetry_log.csv` · Physics Lead signature |

### PQ-PHY-003: All Nine Plants Telemetry Bounds

| | |
| --- | --- |
| **Invariant** | Per-plant bounds from [[Plant-Catalogue]] Section 4.2 |
| **Procedure** | For each of the 9 plants: load plant, run 120 frames, sample all three channels every 10 frames, assert within plant-specific bounds. |
| **Acceptance** | 100% in-bounds for all 9 plants × 3 channels. Zero NaN/Inf across all 9. |
| **Evidence** | `telemetry/all_plants_telemetry_log.csv` with one row per plant · Physics Lead signature |

### PQ-PHY-004: Epistemic Tag Correctness Per Plant

| | |
| --- | --- |
| **Invariant** | M/T/I/A tags match [[Plant-Catalogue]] epistemic column for each plant |
| **Procedure** | For each plant: load, read M/T/I/A tags for I_p, B_T, n_e. Assert match against certified reference. |
| **Acceptance** | All 27 tag assertions pass (9 plants × 3 channels). |
| **Evidence** | `telemetry/epistemic_tag_verification.json` |

### PQ-PHY-005: Epistemic Tag Preservation Across Swap

| | |
| --- | --- |
| **Invariant** | M/T/I/A tags unchanged before and after any plant swap |
| **Procedure** | Record all tags for plant A. Swap to plant B. Record tags. Swap back to A. Assert tags match original. Repeat for 5 different swap pairs. |
| **Acceptance** | Zero tag mutations across all 5 swap pairs. |
| **Evidence** | Pre/post swap tag comparison log · Physics Lead signature |

### PQ-PHY-006: ICF High-Density Normalisation

| | |
| --- | --- |
| **Invariant** | n_e at 10³¹ m⁻³ must normalise to [0.0, 1.0] for the Metal red channel without float overflow |
| **Procedure** | Load inertial plant. Assert renderer red channel is in [0.0, 1.0] f32. Assert no Inf in normalised value. |
| **Acceptance** | Normalised n_e ∈ [0.0, 1.0]. No overflow. |
| **Evidence** | `telemetry/icf_normalisation_log.json` |

### PQ-PHY-007: Negative Value Prohibition

| | |
| --- | --- |
| **Invariant** | I_p, B_T, n_e ≥ 0.0 for all plants at all times |
| **Procedure** | Monitor all three channels for all 9 plants over 120 frames each. Assert no negative values. |
| **Acceptance** | Zero negative values recorded across all 9 plants. |
| **Evidence** | `telemetry/negative_value_scan.csv` |

### PQ-PHY-008: NaN/Inf Injection Response

| | |
| --- | --- |
| **Invariant** | System must enter REFUSED and halt on NaN/Inf — not silently continue or clamp |
| **Procedure** | Inject NaN into I_p for tokamak plant. Verify REFUSED within 100 ms. Verify red error tint active. Open NCR. |
| **Acceptance** | REFUSED state within 100 ms. Red tint active. NCR created. Normal processing stopped. |
| **Evidence** | `telemetry/nan_injection_response_log.json` · Safety Officer co-sign |

---

## PQ-CSE — Control Systems Engineering Protocols

### PQ-CSE-001: All Nine Plants Load Non-Zero Geometry

| | |
| --- | --- |
| **Invariant** | Every plant wireframe must produce vertex_count > 0 |
| **Procedure** | For each of 9 plants: load plant USD, query vertex buffer, assert count > 0, assert no Metal GPU errors. |
| **Acceptance** | All 9 plants return vertex_count > 0. Zero Metal errors. |
| **Evidence** | `geometry/plant_geometry_counts.json` (9 rows) |

### PQ-CSE-002: Minimum Vertex and Index Counts Per Plant

| Plant | Min vertices | Min indices |
| --- | --- | --- |
| tokamak | 48 | 96 |
| stellarator | 48 | 96 |
| spherical_tokamak | 32 | 64 |
| frc | 24 | 48 |
| mirror | 24 | 48 |
| spheromak | 32 | 64 |
| z_pinch | 16 | 32 |
| mif | 40 | 80 |
| inertial | 40 | 80 |

**Acceptance:** All plants meet or exceed their minimum counts.
**Evidence:** `geometry/plant_geometry_counts.json`

### PQ-CSE-003: Continuous Render 300 Seconds — All Plants

| | |
| --- | --- |
| **Invariant** | Frame drop rate < 0.1% over any 60-second window |
| **Procedure** | For each of 9 plants: run render loop for 300 seconds. Collect frame count and drop count. Assert drop rate < 0.1%. |
| **Acceptance** | All 9 plants achieve < 0.1% drop rate over 300 seconds. |
| **Evidence** | `continuous_render_metrics.csv` (9 rows, one per plant) |

### PQ-CSE-004: Plant Swap Latency

| | |
| --- | --- |
| **Invariant** | REQUESTED → VERIFIED must complete in ≤ 3700 ms (sum of all state maximums) |
| **Procedure** | Execute 20 random plant swaps. Time each from REQUESTED to terminal state. Assert all ≤ 3700 ms. |
| **Acceptance** | All 20 swaps complete in ≤ 3700 ms. Zero REFUSED on valid plants. |
| **Evidence** | `swap/swap_latency_log.csv` |

### PQ-CSE-005: Full 81-Swap Permutation Matrix

| | |
| --- | --- |
| **Invariant** | All 9×9 plant-to-plant combinations must reach CALORIE or CURE — never REFUSED |
| **Procedure** | Execute all 81 combinations (including same-plant reload). Record terminal state for each. |
| **Acceptance** | Zero REFUSED states. All 81 swaps reach CALORIE or CURE. |
| **Evidence** | `swap/swap_permutation_matrix.json` (81 entries) |

The full 9×9 matrix must be documented in the evidence file. Each entry records: `from_plant`, `to_plant`, `terminal_state`, `duration_ms`, `timestamp`.

### PQ-CSE-006: REFUSED on Invalid Plant

| | |
| --- | --- |
| **Invariant** | Swap to unknown plant must enter REFUSED, not silent failure |
| **Procedure** | Attempt swap to `plant_id = "unknown"`. Assert REFUSED within 500 ms. Assert red tint active. |
| **Acceptance** | REFUSED state and red tint within 500 ms. |
| **Evidence** | `swap/refused_invalid_plant_log.json` |

### PQ-CSE-007: REFUSED on Mesh Loss

| | |
| --- | --- |
| **Invariant** | Zero-vertex geometry must trigger REFUSED |
| **Procedure** | Load a plant USD file that produces zero vertices. Assert REFUSED is entered. |
| **Acceptance** | REFUSED on zero-vertex geometry. |
| **Evidence** | `swap/refused_mesh_loss_log.json` |

### PQ-CSE-008: Telemetry Colour Channel Validation

| | |
| --- | --- |
| **Invariant** | I_p → blue, B_T → green, n_e → red. All channels ∈ [0.0, 1.0] after normalisation. |
| **Procedure** | Set known telemetry values. Sample rendered pixel colours from Metal layer. Assert channel mapping correct within ±0.02. |
| **Acceptance** | All three channel mappings correct for 5 test value sets across 3 plant kinds. |
| **Evidence** | `colour_mapping_validation.json` |

### PQ-CSE-009 through PQ-CSE-012

| Test ID | Title | Acceptance criterion |
| --- | --- | --- |
| PQ-CSE-009 | Control loop jitter < 1 ms over 1000 cycles | Max jitter < 1 ms |
| PQ-CSE-010 | End-to-end latency WASM → renderer < 5 ms | P99 < 5 ms |
| PQ-CSE-011 | Vertex ABI stride 28 bytes on CERN hardware | Exact match against CI results |
| PQ-CSE-012 | Uniforms ABI stride 64 bytes on CERN hardware | Exact match against CI results |

---

## PQ-QA — Software QA Protocols

### PQ-QA-001: Automated Full Cycle Receipt

| | |
| --- | --- |
| **Procedure** | Execute `zsh scripts/run_full_cycle.sh`. All 5 phases must complete green. |
| **Acceptance** | 32 Rust tests passed. `full_cycle_receipt.json` status = `FULL_CYCLE_GREEN`. GitHub Actions green. |
| **Evidence** | `evidence/full_cycle_receipt.json` · GitHub Actions run URL |

### PQ-QA-002: Swift Continuous Operation Test Suite

| | |
| --- | --- |
| **Procedure** | Execute `swift test --filter PlantContinuousOperationTests`. |
| **Test methods** | `testAllNinePlantsLoadAndRenderContinuously` · `testPlantSwapCycleAllToAll` · `testTelemetryEpistemicBoundary` |
| **Acceptance** | All Swift tests PASS. Zero REFUSED states. |
| **Evidence** | `swift_test_output.txt` |

### PQ-QA-003 through PQ-QA-010

| Test ID | Title | Acceptance criterion |
| --- | --- | --- |
| PQ-QA-003 | Evidence generation script produces 9 plant screenshots | 9 PNG files in `evidence/pq_validation/screenshots/` |
| PQ-QA-004 | Build reproducibility — two clean builds SHA-256 identical | Binary SHA-256 matches between builds |
| PQ-QA-005 | No `target/` in git history | `git log --all -- '**/target/**'` returns zero results |
| PQ-QA-006 | Cargo.lock committed and matches | Zero uncommitted changes to Cargo.lock |
| PQ-QA-007 | Binary size < 5 MB (zero OpenUSD bloat) | `du -h` reports < 5 MB |
| PQ-QA-008 | Instruments: zero memory leaks over 60 seconds | 0 leaked bytes |
| PQ-QA-009 | `timeline_v2.json` present for all 9 plants | 9 files found in `Resources/usd/plants/` |
| PQ-QA-010 | Electronic records audit trail — no force-push after PQ begins | Git log shows linear history |

---

## PQ-SAF — Safety Team Protocols

**Safety Officer must be physically present for all SAF tests.**

### PQ-SAF-001: Invariant Breach — REFUSED and Halt

| | |
| --- | --- |
| **Objective** | Out-of-range telemetry triggers REFUSED and halts processing. Not a silent clamp. |
| **Procedure** | Inject I_p = 999 MA into tokamak plant (far above 2.0 MA maximum). Verify REFUSED within 100 ms. Verify red tint. Verify processing halted. NCR opened. |
| **Acceptance** | REFUSED ≤ 100 ms. Red tint active. Processing halted. NCR auto-created. |
| **Evidence** | Alert log · halt confirmation · NCR reference · Safety Officer signature |

### PQ-SAF-002 through PQ-SAF-008

| Test ID | Title | Witness required | Acceptance |
| --- | --- | --- | --- |
| PQ-SAF-002 | NaN injection → REFUSED across all 3 channels | Safety Officer | REFUSED ≤ 100 ms per channel |
| PQ-SAF-003 | Negative I_p injection → REFUSED | Safety Officer | REFUSED ≤ 100 ms |
| PQ-SAF-004 | CURE state degraded telemetry alert | Safety Officer | Operator alert issued within 500 ms |
| PQ-SAF-005 | Emergency stop halts control loop | Safety Officer + RP | Loop halts ≤ 50 ms |
| PQ-SAF-006 | Process crash → defined safe state | Safety Officer | Safe state entered, no undefined behaviour |
| PQ-SAF-007 | REFUSED NCR workflow completion | QA Manager co-sign | NCR created, routed, closed |
| PQ-SAF-008 | Radiation interlock compatibility | RP Team | System responds per RP SOP |

---

## PQ Requirements Per Plant Kind — Summary

This table maps each plant kind to the specific PQ tests that verify it.

| Plant kind | PHY bounds | PHY-004 epistemic | CSE-001 geometry | CSE-002 min counts | CSE-003 continuous render | CSE-005 swap matrix |
| --- | --- | --- | --- | --- | --- | --- |
| Tokamak | PHY-001, PHY-003 | PHY-004 | CSE-001 | ≥ 48v / 96i | CSE-003 | 9 entries (from + to) |
| Stellarator | PHY-002, PHY-003 | PHY-004 | CSE-001 | ≥ 48v / 96i | CSE-003 | 9 entries |
| Spherical Tokamak | PHY-003 | PHY-004 | CSE-001 | ≥ 32v / 64i | CSE-003 | 9 entries |
| FRC | PHY-003 | PHY-004 | CSE-001 | ≥ 24v / 48i | CSE-003 | 9 entries |
| Mirror | PHY-003 | PHY-004 | CSE-001 | ≥ 24v / 48i | CSE-003 | 9 entries |
| Spheromak | PHY-003 | PHY-004 | CSE-001 | ≥ 32v / 64i | CSE-003 | 9 entries |
| Z-Pinch | PHY-003 | PHY-004 | CSE-001 | ≥ 16v / 32i | CSE-003 | 9 entries |
| MIF | PHY-003 | PHY-004 | CSE-001 | ≥ 40v / 80i | CSE-003 | 9 entries |
| Inertial | PHY-003, PHY-006 | PHY-004 | CSE-001 | ≥ 40v / 80i | CSE-003 | 9 entries |

---

## Evidence Directory Structure

```
evidence/
├── iq_receipt.json
├── oq_receipt.json
├── full_cycle_receipt.json
└── pq_validation/
    ├── PQ_VALIDATION_REPORT.md
    ├── final_receipt.json
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
    └── geometry/
        └── plant_geometry_counts.json
```

All evidence artifacts have a minimum 10-year retention requirement. Git commit SHA and GitHub Actions run URLs are retained permanently.

---

## PQ Execution Schedule

| Phase | Tests | Est. duration | Prerequisite |
| --- | --- | --- | --- |
| 0 | IQ + OQ complete, 32 tests green, CI green | 1 day | None |
| 1 | PQ-PHY-001 through PQ-PHY-008 | 2 days | Phase 0 signed |
| 2 | PQ-CSE-001 through PQ-CSE-012 | 3 days | Phase 1 signed |
| 3 | PQ-QA-001 through PQ-QA-010 | 2 days | Phase 2 signed |
| 4 | PQ-SAF-001 through PQ-SAF-008 | 2 days | Phase 3 signed |
| 5 | Final review + QA release | 1 day | Phase 4 signed, 0 open deviations |

**Total estimated: 11 working days**

---

## Phase Sign-Off

| Phase | Tests executed | Pass / Fail | Signed by | Date |
| --- | --- | --- | --- | --- |
| Physics | PQ-PHY-001 to PQ-PHY-008 | | | |
| CSE | PQ-CSE-001 to PQ-CSE-012 | | | |
| SW QA | PQ-QA-001 to PQ-QA-010 | | | |
| Safety | PQ-SAF-001 to PQ-SAF-008 | | | |
| QA Release | All phases | | | |

---

*END OF DOCUMENT — GFTCL-PQ-002 Rev 1.0*
*GaiaFusion Plant Control System — Performance Qualification Plan*
*GAMP 5 | EU Annex 11 | FDA 21 CFR Part 11 | CERN Research Facility*
