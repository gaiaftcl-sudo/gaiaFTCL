# State Machine — GaiaHealth Biologit Cell

> **States:** 11  
> **Crate:** `biologit_md_engine::state_machine`  
> **Regulation:** FDA 21 CFR Part 11 · EU Annex 11  
> **M/I/A Spine:** enforced at MSL shader level

---

## Overview

The GaiaHealth Biologit Cell is governed by an **11-state machine** that controls every aspect of cell operation — UI layout, Metal render pipeline selection, WASM constitutional check invocation, and CURE emission. No state can be bypassed; all transitions are validated before execution.

This state machine is architecturally identical in structure to the GaiaFTCL Fusion Cell's state machine, differentiated only by domain-specific conditions.

---

## States

```
 0  IDLE                ← entry point, reset state
 1  MOORED              ← Owl identity bound, consent gate open
 2  PREPARED            ← force-field parameters validated
 3  RUNNING             ← MD simulation active
 4  ANALYSIS            ← binding ΔG computation
 5  CURE                ← valid CURE emitted ✓
 6  REFUSED             ← computation rejected (bad ADMET, Assumed-only, etc.)
 7  CONSTITUTIONAL_FLAG ← WASM boundary violated (audit mandatory)
 8  CONSENT_GATE        ← waiting for operator consent signature
 9  TRAINING            ← training_mode=true, no real data
10  AUDIT_HOLD          ← regulatory hold, all writes suspended
```

---

## State Definitions

### IDLE (0)
The cell is powered on but no molecular target is loaded. No computation runs. Any Owl pubkey previously bound is **erased from memory** on entry to IDLE (zero-PII enforcement).

**Forced layout:** Single-window, minimal chrome.  
**Metal opacity:** 100% (static background only).

---

### MOORED (1)
An Owl pubkey has been bound via `moor_owl()`. The pubkey is validated as a secp256k1 compressed key (66 hex chars, 02/03 prefix). Any personal identifier (email, name, SSN) causes immediate transition to REFUSED.

The consent gate is open — the operator must provide a valid `ConsentRecord` (within 5-minute window) before advancing to PREPARED.

**Entry condition:** Valid Owl pubkey provided.  
**Exit conditions:** PREPARED (consent valid) | CONSENT_GATE (consent required) | IDLE (revoke/reset).

---

### PREPARED (2)
Force-field parameters have been validated. All MD simulation parameters are within specification:

- Temperature: 250–450 K
- Pressure: 0.5–500 bar
- Timestep: 0.5–4 fs
- Simulation time: ≥10 ns
- Water box padding: ≥10 Å

**Entry condition:** `validate_ff_parameters()` → `FFValidationResult::Valid`.  
**Exit conditions:** RUNNING | CONSTITUTIONAL_FLAG (WASM check failure).

---

### RUNNING (3)
MD simulation is actively executing. Frame counter increments. Metal renderer ticks each frame. Constitutional substrate is polled on every N frames.

**Entry condition:** From PREPARED.  
**Exit conditions:** ANALYSIS (sim complete) | REFUSED (ADMET failure mid-run) | AUDIT_HOLD.

---

### ANALYSIS (4)
MD simulation complete. Binding ΔG is computed. ADMET score is evaluated. Epistemic tag is finalized. All 8 WASM constitutional checks are invoked.

**Entry condition:** From RUNNING (sim_time_ns ≥ target).  
**Exit conditions:** CURE (all checks pass, M or I epistemic) | REFUSED (any check fails or Assumed-only).

---

### CURE (5)
A valid CURE has been emitted. This is the **terminal success state**. The CURE record is written to the audit log using the Owl pubkey hash (never the raw pubkey, never a name).

**CURE conditions:**
1. `epistemic_tag` = Measured (0) or Inferred (1) — Assumed (2) alone blocks CURE
2. `binding_dg` < 0 (favorable binding)
3. `admet_score` ≥ 0.5
4. All 8 WASM exports return `Valid` / `true`
5. `selectivity_ratio` check passes

**Audit log entry:** `owl_pubkey.chain_hash()` (SHA-256, never raw pubkey).

---

### REFUSED (6)
The computation was rejected. Reasons include: invalid Owl pubkey (personal identifier supplied), ADMET score too low, Assumed-only epistemic chain, force-field bounds violation, PHI detected in input, WASM constitutional check failure.

The REFUSED state is **terminal per session**. The operator must restart the cell (→ IDLE) and address the failure before retrying.

**Fault codes stored:** Never contain personal information. Fault codes reference physical parameters only (e.g., `ASSUMED_BINDING_NOT_VALIDATED`, `ADMET_BELOW_THRESHOLD`).

---

### CONSTITUTIONAL_FLAG (7)
A WASM constitutional boundary has been violated. This state triggers the **alarm_pipeline** in Metal — a pulsing red overlay renders over the entire CAMetalLayer. This state requires mandatory audit review before the cell can return to operation.

**Visual:** `alarm_pipeline` active — pulsing red overlay at 2 Hz.  
**Required:** External audit sign-off before → IDLE.

---

### CONSENT_GATE (8)
Consent is required but has not been provided or has expired (> 5 minutes since grant). The operator must re-sign consent using the Owl private key before computation can proceed.

**5-minute window:** `ConsentRecord.is_valid(now_ms)` — expires after 300,000 ms.

---

### TRAINING (9)
The cell is running in `training_mode = true`. No real biological data is processed. No real CURE is emitted. This state is used by the Swift TestRobit and operator training workflows. All state transitions function normally but outputs are flagged `training_mode: true`.

---

### AUDIT_HOLD (10)
A regulatory hold has been placed on the cell. All writes to the audit log are suspended. The cell cannot transition to RUNNING or CURE while in AUDIT_HOLD. Only a qualified person with the correct Owl signature can release the hold.

---

## Transition Matrix

`✓` = valid transition | `✗` = invalid (returns `OwlError::InvalidTransition`) | `—` = irrelevant

| From \ To | IDLE | MOORED | PREPARED | RUNNING | ANALYSIS | CURE | REFUSED | CONST_FLAG | CONSENT_GATE | TRAINING | AUDIT_HOLD |
|-----------|------|--------|----------|---------|----------|------|---------|------------|--------------|----------|------------|
| **IDLE** | — | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| **MOORED** | ✓ | — | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ |
| **PREPARED** | ✓ | ✗ | — | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ |
| **RUNNING** | ✗ | ✗ | ✗ | — | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ |
| **ANALYSIS** | ✗ | ✗ | ✗ | ✗ | — | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ |
| **CURE** | ✓ | ✗ | ✗ | ✗ | ✗ | — | ✗ | ✗ | ✗ | ✗ | ✗ |
| **REFUSED** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | — | ✗ | ✗ | ✗ | ✗ |
| **CONST_FLAG** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | — | ✗ | ✗ | ✓ |
| **CONSENT_GATE** | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | — | ✗ | ✗ |
| **TRAINING** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | — | ✗ |
| **AUDIT_HOLD** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | — |

---

## Forced Layout Modes

Each state enforces a **forced layout mode** that the Swift/macOS layer must respect. The layout is **not operator-configurable** while in that state.

| State | Layout Mode | Description |
|-------|-------------|-------------|
| IDLE | `idle_overview` | Overview screen, no active computation |
| MOORED | `consent_panel` | Consent and identity panel visible |
| PREPARED | `parameter_review` | Force-field parameters displayed |
| RUNNING | `simulation_live` | Live MD trajectory rendering |
| ANALYSIS | `analysis_results` | Binding ΔG and ADMET scores |
| CURE | `cure_certificate` | CURE record display, audit hash |
| REFUSED | `refusal_report` | Fault code and remediation guidance |
| CONSTITUTIONAL_FLAG | `alarm_full_screen` | Full-screen red alarm, no other UI |
| CONSENT_GATE | `consent_required` | Consent re-entry panel only |
| TRAINING | `training_overlay` | All panels + "TRAINING MODE" overlay |
| AUDIT_HOLD | `audit_hold_screen` | Hold notice, contact info, no computation |

---

## M/I/A Epistemic Spine

Every computational output from GaiaHealth carries an epistemic tag. This is **enforced at the MSL shader level** — the correct Metal pipeline is selected based on the `epistemic_tag` field in `BioligitPrimitive`.

| Tag | Value | Meaning | Metal Pipeline | Alpha |
|-----|-------|---------|----------------|-------|
| Measured (M) | 0 | Directly measured from MD trajectory | `m_pipeline` | 1.0 (opaque) |
| Inferred (I) | 1 | Computed from model with validated assumptions | `i_pipeline` | 0.6 (translucent, alpha blend) |
| Assumed (A) | 2 | Based on unvalidated assumptions | `a_pipeline` | 0.3 (stippled, checkerboard discard) |

**CURE requirement:** The epistemic chain must contain at least one M or I node. An Assumed-only chain → REFUSED with fault `ASSUMED_BINDING_NOT_VALIDATED`.

**Constitutional flag:** `epistemic_chain_validate()` in the WASM substrate validates the chain. An invalid chain → CONSTITUTIONAL_FLAG.

---

## Single-Window Constraint (FDA 21 CFR Part 11)

GaiaHealth enforces a **single-window lock** per FDA 21 CFR Part 11. The `NSWindow` singleton cannot be split, tabbed, or duplicated while the cell is in RUNNING, ANALYSIS, or CURE state. This prevents UI state fragmentation in audit trails.

---

## MTLLoadActionClear Requirement

Every Metal frame **must** begin with `MTLLoadActionClear`. This prevents ghost artifacts from prior frames — a requirement under FDA 21 CFR Part 11 for electronic display integrity.

---

## Zero-PII on IDLE Entry

When the state machine transitions to IDLE from any state, the Owl pubkey is **zeroed from memory** immediately before the transition completes. This is enforced in `bio_state_transition()` (C FFI) and in the `validate_transition()` function.

Fault codes and audit entries stored on REFUSED or CONSTITUTIONAL_FLAG contain **only the pubkey hash** (`owl_pubkey.chain_hash()`), never the raw pubkey, never a name, never any personal identifier.
