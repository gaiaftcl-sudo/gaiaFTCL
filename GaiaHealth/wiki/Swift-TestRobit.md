# Swift TestRobit — GaiaHealth Biologit Cell

> **Package:** `GaiaHealth/swift_testrobit/`  
> **Type:** Swift Package Manager executable (macOS 14+)  
> **Role:** GAMP 5 OQ acceptance harness  
> **Total Tests:** 58 across 5 suites  
> **Receipt:** `evidence/testrobit_receipt.json`

---

## Overview

The Swift TestRobit is the **GxP acceptance harness** for the GaiaHealth Biologit Cell. It runs in `training_mode = true` (no live biological data, no real CURE emission during testing), exercises all five architectural layers via the C FFI bridge, and writes an immutable JSON receipt that serves as OQ evidence under GAMP 5.

The TestRobit is architecturally identical in purpose to the TestRobit for the GaiaFTCL Fusion Cell, but is **100% on the Biologit cell architecture** — it links `libbiologit_md_engine.a` and `libgaia_health_renderer.a`, not the Fusion libraries.

---

## Architecture

```
swift_testrobit/
├── Package.swift                        # Swift 5.9, macOS 14+, linked libraries
└── Sources/
    └── SwiftTestRobit/
        ├── main.swift                   # Harness entry point, receipt writer
        ├── BioStateTests.swift          # Suite 1 — C FFI bridge (12 tests)
        ├── StateMachineTests.swift      # Suite 2 — 11-state machine (10 tests)
        ├── WalletTests.swift            # Suite 3 — Zero-PII wallet (10 tests)
        ├── EpistemicTests.swift         # Suite 4 — M/I/A renderer (10 tests)
        └── ConstitutionalTests.swift    # Suite 5 — WASM 8-export (16 tests)
```

**Linked native libraries:**

| Library | Provides |
|---------|----------|
| `libbiologit_md_engine.a` | `bio_state_*` C FFI surface |
| `libgaia_health_renderer.a` | `gaia_health_renderer_*` C FFI surface |
| `Metal.framework` | GPU pipeline validation |
| `QuartzCore.framework` | CAMetalLayer |
| `AppKit.framework` | NSWindow single-window lock |

---

## Building

### Step 1 — Build the Rust libraries

```bash
cd FoT8D/GaiaHealth
cargo build --release

# Static libs will be at:
# target/release/libbiologit_md_engine.a
# target/release/libgaia_health_renderer.a
```

### Step 2 — Copy libs to TestRobit search path

```bash
cp target/release/libbiologit_md_engine.a swift_testrobit/
cp target/release/libgaia_health_renderer.a swift_testrobit/
```

### Step 3 — Build and run the TestRobit

```bash
cd swift_testrobit
swift build
swift run SwiftTestRobit
```

### Expected output (all pass)

```
══════════════════════════════════════════════
  GaiaHealth Swift TestRobit — Biologit Cell
  GAMP 5 OQ Harness | training_mode=true
══════════════════════════════════════════════

[Suite 1/5] BioStateTests (12 tests)
  ✓ BioState-TP-001  biostate_create_returns_nonnull
  ✓ BioState-TP-002  biostate_initial_state_is_idle
  ...
  ✓ BioState-RG-001  biostate_zero_pii_in_training_mode
  Suite 1 PASSED (12/12)

[Suite 2/5] StateMachineTests (10 tests)
  ...
  Suite 2 PASSED (10/10)

[Suite 3/5] WalletTests (10 tests)
  ...
  Suite 3 PASSED (10/10)

[Suite 4/5] EpistemicTests (10 tests)
  ...
  Suite 4 PASSED (10/10)

[Suite 5/5] ConstitutionalTests (16 tests)
  ...
  Suite 5 PASSED (16/16)

══════════════════════════════════════════════
  TOTAL: 58/58 PASSED | FAILED: 0
  Receipt: evidence/testrobit_receipt.json
══════════════════════════════════════════════
```

---

## Suite 1 — BioStateTests (12 tests)

Tests the C FFI bridge to `libbiologit_md_engine.a` using `@_silgen_name` declarations.

| Test ID | Name | Description |
|---------|------|-------------|
| BioState-TP-001 | biostate_create_returns_nonnull | `bio_state_create()` returns non-null pointer |
| BioState-TP-002 | biostate_initial_state_is_idle | Initial state = `IDLE (0)` |
| BioState-TP-003 | biostate_initial_frame_count_zero | Frame counter starts at 0 |
| BioState-TP-004 | biostate_increment_frame_advances | `bio_state_increment_frame()` increments by 1 |
| BioState-TP-005 | biostate_transition_idle_to_moored | IDLE → MOORED valid with Owl pubkey |
| BioState-TP-006 | biostate_moor_owl_accepts_valid_pubkey | Valid 66-char hex 02/03 pubkey accepted |
| BioState-TN-001 | biostate_moor_owl_rejects_email | Email string → `REFUSED` |
| BioState-TN-002 | biostate_moor_owl_rejects_name | Personal name string → `REFUSED` |
| BioState-TN-003 | biostate_invalid_transition_rejected | IDLE → CURE (skip states) → rejected |
| BioState-TC-001 | biostate_epistemic_tag_default_measured | Default epistemic tag = `Measured (0)` |
| BioState-TI-001 | biostate_destroy_does_not_crash | `bio_state_destroy()` on valid pointer is safe |
| BioState-RG-001 | biostate_zero_pii_in_training_mode | `get_state()` returns only opaque integer, no strings |

---

## Suite 2 — StateMachineTests (10 tests)

Tests all 11 states and enforces the transition matrix.

| Test ID | Name | Description |
|---------|------|-------------|
| StateMachine-TP-001 | idle_is_initial_state | State machine starts in IDLE |
| StateMachine-TP-002 | full_cure_path | IDLE→MOORED→PREPARED→RUNNING→ANALYSIS→CURE |
| StateMachine-TP-003 | refused_from_running | RUNNING→REFUSED on ADMET failure |
| StateMachine-TP-004 | constitutional_flag_from_prepared | PREPARED→CONSTITUTIONAL_FLAG |
| StateMachine-TP-005 | consent_gate_from_moored | MOORED→CONSENT_GATE |
| StateMachine-TP-006 | audit_hold_reachable | Any state → AUDIT_HOLD |
| StateMachine-TP-007 | training_mode_state | IDLE→TRAINING reachable |
| StateMachine-TN-001 | idle_to_cure_rejected | IDLE→CURE (invalid skip) → error |
| StateMachine-TN-002 | refused_to_running_rejected | REFUSED→RUNNING → error (no re-entry) |
| StateMachine-TC-001 | cure_requires_m_or_i | CURE unreachable from Assumed-only epistemic chain |

---

## Suite 3 — WalletTests (10 tests)

Tests the zero-PII mandate on `~/.gaiahealth/wallet.key`.

| Test ID | Name | Description |
|---------|------|-------------|
| Wallet-IQ-001 | wallet_file_exists | `~/.gaiahealth/wallet.key` present |
| Wallet-IQ-002 | wallet_mode_600 | File mode = `0o600` (owner read-only) |
| Wallet-IQ-003 | wallet_is_valid_json | File parses as valid JSON |
| Wallet-IQ-004 | wallet_has_required_fields | Has: cell_id, wallet_address, private_entropy, generated_at |
| Wallet-TP-001 | wallet_address_gaiahealth1_prefix | `wallet_address` starts with `gaiahealth1` |
| Wallet-TP-002 | cell_id_is_64_hex_chars | `cell_id` = 64 lowercase hex chars |
| Wallet-TP-003 | pii_stored_is_false | `"pii_stored": false` present in JSON |
| Wallet-TN-001 | wallet_contains_no_phi | Wallet JSON absent of: name, email, dob, ssn, mrn, patient, insurance, address, phone, birth, gender, race, ethnicity, diagnosis |
| Wallet-TN-002 | wallet_address_not_email | `wallet_address` does not contain `@` |
| Wallet-RG-001 | wallet_address_length_check | Address length ≥ 43 chars (prefix + 38 hex) |

---

## Suite 4 — EpistemicTests (10 tests)

Tests the M/I/A epistemic renderer state via `libgaia_health_renderer.a`.

| Test ID | Name | Description |
|---------|------|-------------|
| Epistemic-TP-001 | renderer_create_returns_nonnull | `gaia_health_renderer_create()` non-null |
| Epistemic-TP-002 | default_epistemic_tag_measured | Default = `Measured (0)` |
| Epistemic-TP-003 | set_measured_returns_1_0_alpha | Set Measured → Metal alpha = 1.0 (opaque) |
| Epistemic-TP-004 | set_inferred_returns_0_6_alpha | Set Inferred → Metal alpha = 0.6 (translucent) |
| Epistemic-TP-005 | set_assumed_returns_0_3_alpha | Set Assumed → Metal alpha = 0.3 (checkerboard) |
| Epistemic-TP-006 | frame_tick_advances | `tick_frame()` increments frame counter |
| Epistemic-TC-001 | cure_requires_m_or_i | Assumed tag → CURE blocked |
| Epistemic-TN-001 | invalid_tag_value_rejected | Tag value 99 → rejected |
| Epistemic-TI-001 | renderer_destroy_safe | `gaia_health_renderer_destroy()` safe on valid pointer |
| Epistemic-RG-002 | vertex_stride_constant | `GAIA_HEALTH_VERTEX_STRIDE` = 32 bytes (ABI lock) |

---

## Suite 5 — ConstitutionalTests (16 tests)

Tests all 8 mandatory WASM exports via WKWebView.

> **Note:** This suite will `SKIP` gracefully if `wasm_constitutional/pkg/gaia_health_substrate.js` has not been built. Run `wasm-pack build` first to enable.

| Test ID | Name | WASM Export |
|---------|------|-------------|
| Constitutional-TC-001 | binding_check_valid_inputs | `binding_constitutional_check` |
| Constitutional-TC-002 | binding_check_rejects_extreme_dg | `binding_constitutional_check` (ΔG > 0) |
| Constitutional-TC-003 | admet_check_all_pass | `admet_bounds_check` (all in range) |
| Constitutional-TC-004 | admet_check_rejects_high_logp | `admet_bounds_check` (logP > 5) |
| Constitutional-TC-005 | phi_check_rejects_ssn | `phi_boundary_check` (SSN pattern) |
| Constitutional-TC-006 | phi_check_rejects_email | `phi_boundary_check` (email) |
| Constitutional-TC-007 | phi_check_accepts_hash | `phi_boundary_check` (64-char hex OK) |
| Constitutional-TC-008 | epistemic_chain_measured_valid | `epistemic_chain_validate` (Measured) |
| Constitutional-TC-009 | epistemic_chain_assumed_invalid | `epistemic_chain_validate` (Assumed→CURE) |
| Constitutional-TC-010 | consent_valid_within_5min | `consent_validity_check` (t < 300s) |
| Constitutional-TC-011 | consent_expired_after_5min | `consent_validity_check` (t > 300s) |
| Constitutional-TC-012 | force_field_valid_params | `force_field_bounds_check` (all in range) |
| Constitutional-TC-013 | force_field_rejects_bad_temp | `force_field_bounds_check` (T > 450K) |
| Constitutional-TC-014 | selectivity_check_high_ratio | `selectivity_check` (ratio > 100) |
| Constitutional-TC-015 | selectivity_check_low_ratio | `selectivity_check` (ratio < 10 → warn) |
| Constitutional-TC-016 | epistemic_tag_export | `get_epistemic_tag` returns 0/1/2 |

---

## GxP Receipt Format

`evidence/testrobit_receipt.json`

```json
{
  "phase": "OQ",
  "cell": "GaiaHealth-Biologit",
  "timestamp": "2026-04-16T12:00:00Z",
  "training_mode": true,
  "total_tests": 58,
  "passed": 58,
  "failed": 0,
  "skipped": 0,
  "suites": {
    "BioStateTests":        { "total": 12, "passed": 12, "failed": 0 },
    "StateMachineTests":    { "total": 10, "passed": 10, "failed": 0 },
    "WalletTests":          { "total": 10, "passed": 10, "failed": 0 },
    "EpistemicTests":       { "total": 10, "passed": 10, "failed": 0 },
    "ConstitutionalTests":  { "total": 16, "passed": 16, "failed": 0 }
  },
  "status": "PASS"
}
```

The process exits `0` on all-pass, `1` on any failure. In CI, a non-zero exit blocks promotion to PQ.

---

## Comparison with GaiaFTCL TestRobit

The GaiaFTCL Fusion Cell has its own Swift TestRobit. Key differences:

| Aspect | GaiaFTCL TestRobit | GaiaHealth TestRobit |
|--------|-------------------|---------------------|
| Linked library | `librust_fusion_usd_parser.a` + `libgaia_metal_renderer.a` | `libbiologit_md_engine.a` + `libgaia_health_renderer.a` |
| Wallet prefix tested | `gaia1` | `gaiahealth1` |
| Total tests | varies (see GAIAFTCL wiki) | 58 |
| Constitutional suite | Fusion WASM exports | Biologit WASM exports (8 exports) |
| Domain | Plasma / τ (Bitcoin height) | Molecular dynamics / ΔG |
| Receipt location | `GAIAFTCL/evidence/` | `GaiaHealth/evidence/` |

Both TestRobits share the **same architectural pattern** and use the same `shared/wallet_core` and `shared/owl_protocol` crates.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed — OQ evidence written |
| 1 | One or more tests failed — BLOCK PQ promotion |
