# WASM Constitutional Substrate — GaiaHealth Biologit Cell

> **Crate:** `wasm_constitutional`  
> **Runtime:** WKWebView (WebAssembly sandbox)  
> **Exports:** 8 mandatory  
> **Role:** Operator visibility layer (NOT the safety enforcer)  
> **GxP Tests:** 16

---

## Overview

The WASM Constitutional Substrate runs inside a WKWebView sandbox and exposes **8 mandatory JavaScript-callable exports** that allow the operator to inspect the constitutional validity of computational inputs and outputs. 

**Important:** The WASM substrate is the **operator visibility layer** — it makes compliance checks observable and auditable. It is NOT the primary safety enforcer. Rust is. The Rust state machine enforces all hard boundaries independently. The WASM layer makes those checks **transparent to operators and regulators**.

**See also:** **[GH-S4C4-COMM-001](../docs/S4_C4_COMMUNION_UI_SPEC.md)** — future global WASM shell / plugin composition for **S4↔C4 communion** (roadmap; does not replace the eight exports documented here unless change-controlled).

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  GaiaHealth macOS App                               │
│                                                     │
│  ┌─────────────────┐    ┌──────────────────────┐   │
│  │  Rust FFI Core  │    │  WKWebView           │   │
│  │  (safety owner) │    │  ┌────────────────┐  │   │
│  │  - state machine│    │  │ WASM           │  │   │
│  │  - force field  │    │  │ Constitutional │  │   │
│  │  - epistemic    │    │  │ Substrate      │  │   │
│  │  - owl protocol │    │  │ (8 exports)    │  │   │
│  └────────┬────────┘    │  └───────┬────────┘  │   │
│           │             │          │            │   │
│           └─────────────┼──────────┘            │   │
│                Swift bridge                     │   │
└─────────────────────────────────────────────────┘
```

---

## Building the WASM Module

```bash
cd FoT8D/cells/health/wasm_constitutional

# Install wasm-pack if not present
cargo install wasm-pack

# Build for web target (produces pkg/ directory)
wasm-pack build --target web

# Output:
# pkg/gaia_health_substrate.js
# pkg/gaia_health_substrate_bg.wasm
# pkg/gaia_health_substrate.d.ts
```

The IQ install script (`scripts/iq_install.sh`) runs this build automatically in Phase 4.

---

## The 8 Mandatory Exports

### Export 1 — `binding_constitutional_check`

**Purpose:** Validates that a binding free energy value is within constitutional bounds.

```typescript
binding_constitutional_check(
    binding_dg: number,      // kcal/mol — must be ≤ 0 for favorable binding
    admet_score: number,     // 0.0–1.0 — must be ≥ 0.5
    epistemic_tag: number    // 0=M, 1=I, 2=A
) → { valid: boolean, alarm: boolean, message: string }
```

**Constitutional bounds:**
- `binding_dg` ≤ 0.0 (favorable) or error
- `admet_score` ∈ [0.0, 1.0]
- `epistemic_tag` ∈ {0, 1, 2}
- `alarm: true` → triggers CONSTITUTIONAL_FLAG state

---

### Export 2 — `admet_bounds_check`

**Purpose:** Validates all five ADMET parameters independently.

```typescript
admet_bounds_check(
    logp: number,           // Lipophilicity — Lipinski rule ≤ 5
    mol_weight: number,     // g/mol — Lipinski rule ≤ 500
    hbd: number,            // H-bond donors — Lipinski rule ≤ 5
    hba: number,            // H-bond acceptors — Lipinski rule ≤ 10
    tpsa: number            // Topological polar surface area — ≤ 140 Å²
) → { valid: boolean, violations: string[], composite_score: number }
```

**Lipinski Rule of Five enforcement:**
- logP > 5 → violation `LIPINSKI_LOGP`
- molecular_weight > 500 → violation `LIPINSKI_MW`
- H-bond donors > 5 → violation `LIPINSKI_HBD`
- H-bond acceptors > 10 → violation `LIPINSKI_HBA`
- TPSA > 140 → violation `TPSA_EXCEEDED`

Three or more violations → `valid: false`.

---

### Export 3 — `phi_boundary_check`

**Purpose:** Validates that an input string contains no Protected Health Information.

```typescript
phi_boundary_check(
    input: string           // Any string to be validated
) → { valid: boolean, phi_detected: boolean, pattern: string | null }
```

**PHI detection patterns:**
- SSN: `\d{3}-\d{2}-\d{4}` pattern
- Email: `@` present with surrounding text
- Names: non-hex ASCII strings > 3 chars that aren't numeric
- MRN: "MRN", "mrn", "patient" keywords
- DOB: date-like patterns (MM/DD/YYYY, YYYY-MM-DD)
- Phone: `\d{3}[.-]\d{3}[.-]\d{4}` pattern

**Accepts:**
- 64-char hex SHA-256 hashes (cell IDs, pubkey hashes)
- 66-char hex secp256k1 pubkeys
- Numeric-only strings (molecule IDs, residue indices)

---

### Export 4 — `epistemic_chain_validate`

**Purpose:** Validates that an epistemic chain supports CURE emission.

```typescript
epistemic_chain_validate(
    chain: number[]         // Array of epistemic tags [0=M, 1=I, 2=A]
) → { valid: boolean, permits_cure: boolean, weakest_link: number }
```

**Rules:**
- Chain with at least one M (0) or I (1) → `permits_cure: true`
- All-Assumed chain → `permits_cure: false` (fault: `ASSUMED_BINDING_NOT_VALIDATED`)
- `weakest_link` = maximum value in chain (higher = weaker)

---

### Export 5 — `consent_validity_check`

**Purpose:** Validates that a consent record is current and within the 5-minute window.

```typescript
consent_validity_check(
    granted_at_ms: number,  // Unix milliseconds when consent was granted
    now_ms: number,         // Current Unix milliseconds
    scope: string           // Consent scope (e.g., "ADMET_PERSONALIZATION")
) → { valid: boolean, expired: boolean, seconds_remaining: number }
```

**5-minute window:** `now_ms - granted_at_ms < 300_000` (300 seconds).

Expired consent → `CONSENT_GATE` state.

---

### Export 6 — `force_field_bounds_check`

**Purpose:** Validates that MD simulation parameters are within constitutional bounds.

```typescript
force_field_bounds_check(
    temperature_k: number,  // Kelvin — valid: 250–450
    pressure_bar: number,   // bar — valid: 0.5–500
    timestep_fs: number,    // femtoseconds — valid: 0.5–4.0
    sim_time_ns: number,    // nanoseconds — minimum: 10.0
    water_padding_a: number // Ångstroms — minimum: 10.0
) → { valid: boolean, violations: string[] }
```

**Violation codes:**
- `TEMPERATURE_OUT_OF_RANGE` (not 250–450 K)
- `PRESSURE_OUT_OF_RANGE` (not 0.5–500 bar)
- `TIMESTEP_OUT_OF_RANGE` (not 0.5–4.0 fs)
- `SIMULATION_TOO_SHORT` (< 10 ns)
- `WATER_PADDING_INSUFFICIENT` (< 10 Å)

---

### Export 7 — `selectivity_check`

**Purpose:** Validates target vs. off-target selectivity ratio.

```typescript
selectivity_check(
    target_ic50: number,    // nM — target inhibition
    off_target_ic50: number // nM — off-target inhibition
) → { valid: boolean, ratio: number, selectivity_class: string }
```

**Selectivity classes:**
- `ratio ≥ 100` → `HIGH_SELECTIVITY` (preferred for CURE)
- `10 ≤ ratio < 100` → `MODERATE_SELECTIVITY` (valid with I epistemic)
- `ratio < 10` → `LOW_SELECTIVITY` (REFUSED if A epistemic)

---

### Export 8 — `get_epistemic_tag`

**Purpose:** Returns the canonical epistemic tag for a given computation context.

```typescript
get_epistemic_tag(
    source_type: number     // 0=direct measurement, 1=model, 2=literature estimate
) → { tag: number, label: string }
// Returns: { tag: 0, label: "Measured" } | { tag: 1, label: "Inferred" } | { tag: 2, label: "Assumed" }
```

This export is the bridge between the computational source type and the `EpistemicTag` enum that drives the Metal render pipeline selection.

---

## GxP Test Coverage

All 8 exports are tested by the `ConstitutionalTests` suite in the Swift TestRobit (16 tests):

| Export | Tests |
|--------|-------|
| `binding_constitutional_check` | TC-001, TC-002 |
| `admet_bounds_check` | TC-003, TC-004 |
| `phi_boundary_check` | TC-005, TC-006, TC-007 |
| `epistemic_chain_validate` | TC-008, TC-009 |
| `consent_validity_check` | TC-010, TC-011 |
| `force_field_bounds_check` | TC-012, TC-013 |
| `selectivity_check` | TC-014, TC-015 |
| `get_epistemic_tag` | TC-016 |

---

## Cargo.toml Dependencies

```toml
[package]
name    = "wasm-constitutional"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
wasm-bindgen = "0.2"
serde        = { version = "1", features = ["derive"] }
serde_json   = "1"

[profile.release]
opt-level = "z"   # minimise WASM binary size
```

---

## Security Model

The WASM substrate runs in the WKWebView sandbox, which enforces:

1. **No filesystem access** — WASM cannot read `~/.gaiahealth/wallet.key`
2. **No network access** — WKWebView is loaded with no-network content rules
3. **No shared memory with Rust** — all values pass through the Swift WKWebView message bridge
4. **Immutable code** — the `.wasm` binary is hash-verified by the IQ script on each launch

**The WASM module cannot:**
- Access or modify the wallet
- Initiate state transitions (Rust owns the state machine)
- Write to the audit log
- Access any personally identifiable information (it never receives any)

**The WASM module can:**
- Validate numerical inputs against constitutional bounds
- Return boolean/structured results to the Swift layer
- Trigger operator alerts that Rust then validates independently
