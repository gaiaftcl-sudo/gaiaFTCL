# OQ — Operational Qualification — GaiaHealth Biologit Cell

> **Executor:** Swift TestRobit (`swift_testrobit/`)  
> **GAMP Phase:** OQ (Phase 3 of 4)  
> **Prerequisite:** IQ PASS  
> **Required before:** PQ  
> **Receipt:** `evidence/testrobit_receipt.json`

---

## Purpose

Operational Qualification (OQ) stress-tests every system function against its design specification. All 11 states must be reachable; all invalid transitions must be rejected; all M/I/A epistemic paths must resolve correctly; the wallet must be free of PII; and all 8 WASM constitutional exports must behave as specified.

OQ is executed entirely by the **Swift TestRobit** — a deterministic, automated acceptance harness that runs in `training_mode = true`. No real biological data is used during OQ.

---

## Running OQ

### Prerequisites

1. IQ must be PASS (`evidence/iq_receipt.json` with `"status": "PASS"`)
2. Rust libraries must be built: `cargo build --release`
3. Static libs must be in the TestRobit search path

```bash
# From FoT8D/cells/health/
cargo build --release

cp target/release/libbiologit_md_engine.a swift_testrobit/
cp target/release/libgaia_health_renderer.a swift_testrobit/
```

### Run the TestRobit

```bash
cd swift_testrobit
swift build
swift run SwiftTestRobit
```

### Expected result

```
══════════════════════════════════════════════
  GaiaHealth Swift TestRobit — Biologit Cell
  GAMP 5 OQ Harness | training_mode=true
══════════════════════════════════════════════
  Suite 1/5 PASSED (12/12)
  Suite 2/5 PASSED (10/10)
  Suite 3/5 PASSED (10/10)
  Suite 4/5 PASSED (10/10)
  Suite 5/5 PASSED (16/16)
──────────────────────────────────────────────
  TOTAL: 58/58 PASSED | FAILED: 0
  Receipt: evidence/testrobit_receipt.json
══════════════════════════════════════════════
Process exited with code 0
```

---

## OQ Test Series

### IQ Series — Installation / Compilation (4 tests)

Verifies the runtime installation under the test harness.

| ID | Test | Verification |
|----|------|-------------|
| IQ-001 | Libraries link without symbol errors | All `@_silgen_name` declarations resolve |
| IQ-002 | bio_state_create returns non-null | C FFI pointer valid |
| IQ-003 | gaia_health_renderer_create returns non-null | Renderer FFI pointer valid |
| IQ-004 | Wallet file exists and parses | `~/.gaiahealth/wallet.key` readable and valid JSON |

---

### TP Series — Positive Paths (8 tests)

Validates all success paths through the system.

| ID | Test | Verification |
|----|------|-------------|
| TP-001 | IDLE → MOORED with valid Owl pubkey | State = 1 after `moor_owl(valid_pubkey)` |
| TP-002 | MOORED → PREPARED | Force-field params valid → state = 2 |
| TP-003 | PREPARED → RUNNING | Start simulation → state = 3 |
| TP-004 | RUNNING → ANALYSIS | Simulation completes → state = 4 |
| TP-005 | ANALYSIS → CURE (Measured epistemic) | All WASM checks pass, M tag → state = 5 |
| TP-006 | ANALYSIS → CURE (Inferred epistemic) | All WASM checks pass, I tag → state = 5 |
| TP-007 | CURE → IDLE (reset) | Session complete → back to 0 |
| TP-008 | IDLE → TRAINING | `training_mode=true` → state = 9 |

---

### TN Series — Negative / Malformed Input (6 tests)

Validates all rejection paths.

| ID | Test | Verification |
|----|------|-------------|
| TN-001 | Email as Owl pubkey → REFUSED | `moor_owl("patient@example.com")` → state = 6 |
| TN-002 | Name as Owl pubkey → REFUSED | `moor_owl("John Smith")` → state = 6 |
| TN-003 | Invalid transition IDLE → CURE | Returns error, state unchanged |
| TN-004 | Assumed-only epistemic → REFUSED | All-A chain → cannot reach CURE |
| TN-005 | ADMET score < 0.5 → REFUSED | `admet_score = 0.3` → state = 6 |
| TN-006 | Temperature out of range → not PREPARED | `temperature_k = 600` → `FFValidationResult::Invalid` |

---

### TR Series — Type Layout / ABI Regression (5 tests)

Validates the `BioligitPrimitive` ABI has not drifted.

| ID | Test | Verification |
|----|------|-------------|
| TR-001 | `BioligitPrimitive` size = 96 bytes | Swift `MemoryLayout<BioligitPrimitive>.size == 96` |
| TR-002 | `BioligitPrimitive` alignment = 8 bytes | `MemoryLayout<BioligitPrimitive>.alignment == 8` |
| TR-003 | `binding_dg` at offset 20 | `MemoryLayout<BioligitPrimitive>.offset(of: \.binding_dg) == 20` |
| TR-004 | `epistemic_tag` at offset 28 | `MemoryLayout<BioligitPrimitive>.offset(of: \.epistemic_tag) == 28` |
| TR-005 | `GAIA_HEALTH_VERTEX_STRIDE` = 32 | Constant matches Metal vertex descriptor |

---

### TC Series — Constitutional Checks (6 tests)

Validates the constitutional boundaries are enforced.

| ID | Test | Verification |
|----|------|-------------|
| TC-001 | CURE requires M or I epistemic | Assumed-only → REFUSED |
| TC-002 | CONSTITUTIONAL_FLAG triggers alarm pipeline | State 7 → `alarm_pipeline` active |
| TC-003 | CONSENT_GATE blocks advancement | Expired consent → cannot reach PREPARED |
| TC-004 | AUDIT_HOLD blocks RUNNING | State 10 → cannot transition to 3 |
| TC-005 | Force-field validation blocks PREPARED on bad params | Invalid params → stays in MOORED |
| TC-006 | PHI in PDB input → rejected | SSN/email in PDB REMARK → `phi_boundary_check` → REFUSED |

---

### TI Series — Integration (5 tests)

End-to-end tests across the Rust FFI → Swift boundary.

| ID | Test | Verification |
|----|------|-------------|
| TI-001 | Full CURE path end-to-end (training_mode) | All 6 state transitions, receipt written |
| TI-002 | Renderer and state machine frame sync | Frame counter increments in sync |
| TI-003 | Wallet → Owl → MOORED integration | Wallet cell_id + Owl pubkey → MOORED state |
| TI-004 | WASM check → Rust state sync | WASM `binding_constitutional_check` → Rust CONSTITUTIONAL_FLAG |
| TI-005 | Destroy both libraries, no crash | `bio_state_destroy` + `gaia_health_renderer_destroy` clean |

---

### RG Series — Regression Guards (4 tests)

Permanent ABI and behaviour locks.

| ID | Test | Verification |
|----|------|-------------|
| RG-001 | Wallet JSON has zero PHI | 14 patterns absent from wallet JSON |
| RG-002 | `BioligitPrimitive` ABI size lock | 96 bytes (cannot change without breaking this test) |
| RG-003 | Vertex stride constant | `GAIA_HEALTH_VERTEX_STRIDE` = 32 (MSL shader must match) |
| RG-004 | Epistemic tag encoding | M=0, I=1, A=2 (cannot reorder without protocol break) |

---

## OQ Receipt

Written to `evidence/testrobit_receipt.json` on all-pass:

```json
{
  "phase": "OQ",
  "cell": "GaiaHealth-Biologit",
  "gamp_category": 5,
  "timestamp": "2026-04-16T12:00:00Z",
  "training_mode": true,
  "total_tests": 58,
  "passed": 58,
  "failed": 0,
  "skipped": 0,
  "suites": {
    "BioStateTests": {
      "total": 12, "passed": 12, "failed": 0,
      "series": ["IQ", "TP", "TN", "TC", "TI", "RG"]
    },
    "StateMachineTests": {
      "total": 10, "passed": 10, "failed": 0,
      "series": ["TP", "TN", "TC"]
    },
    "WalletTests": {
      "total": 10, "passed": 10, "failed": 0,
      "series": ["IQ", "TP", "TN", "RG"]
    },
    "EpistemicTests": {
      "total": 10, "passed": 10, "failed": 0,
      "series": ["TP", "TC", "TN", "TI", "RG"]
    },
    "ConstitutionalTests": {
      "total": 16, "passed": 16, "failed": 0,
      "series": ["TC"],
      "wasm_exports_tested": 8
    }
  },
  "status": "PASS"
}
```

---

## OQ Exit Criteria

All of the following must be true:

- [ ] IQ receipt exists and is `"status": "PASS"`
- [ ] All 58 Swift TestRobit tests pass (0 failures)
- [ ] All 38 Rust GxP tests pass (verified in IQ, re-verified in OQ run)
- [ ] No test in SKIP state (ConstitutionalTests may skip if WASM not built — must be resolved before OQ PASS)
- [ ] Process exits with code 0
- [ ] `evidence/testrobit_receipt.json` written with `"status": "PASS"`

---

## OQ Failure Handling

| Failure | Action |
|---------|--------|
| Any test FAIL | Identify failing test ID, fix root cause, re-run full OQ suite from scratch |
| ConstitutionalTests SKIP | Build WASM (`wasm-pack build`) and re-run |
| Library link error | Rebuild Rust with `cargo build --release`, re-copy .a files |
| Wallet PHI assertion fails | Delete `~/.gaiahealth/wallet.key`, re-run IQ Phase 3 |

**OQ must be re-run from scratch (all 58 tests) after any code change.** Partial re-runs are not accepted as OQ evidence.

---

## Next Step

After OQ PASS → proceed to **[PQ — Performance Qualification](./PQ-Performance-Qualification.md)**
