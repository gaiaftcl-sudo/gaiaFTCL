# GaiaFTCL Fusion Cell — Functional Specification
## Document ID: GFTCL-FS-001
## Version: 1.0 | Date: 2026-04-16
## Status: APPROVED FOR VALIDATION
## Owner: Richard Gillespie — FortressAI Research Institute, Norwich CT
## Patents: USPTO 19/460,960 | USPTO 19/096,071
## Framework: GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11 | CERN Safety

---

## 1. Purpose and Scope

This Functional Specification defines the externally observable behaviour of the **GaiaFTCL Fusion Cell** — a GAMP 5 Category 5 custom software component that provides validated plasma physics telemetry rendering, sovereign cell identity, and epistemic classification for fusion energy research at CERN.

This document governs:
- The `gaia-metal-renderer` Rust crate (Metal GPU rendering, TauState, FFI bridge)
- The `rust_fusion_usd_parser` Rust crate (OpenUSD parsing, vQbitPrimitive ABI)
- The shared crates (`wallet_core`, `owl_protocol`) as consumed by the fusion cell
- The IQ/OQ/PQ validation scripts (`scripts/iq_install.sh`, `scripts/oq_validate.sh`, `scripts/run_full_cycle.sh`)

**Out of scope:** The GaiaFusion orchestration macOS app (`cells/fusion/macos/GaiaFusion/`), NATS server infrastructure, CERN network topology, and the GaiaHealth Biologit Cell (separate FS: GH-FS-001).

---

## 2. System Context

The GaiaFTCL Fusion Cell operates as a sovereign Cell Library (`staticlib`) loaded by the GaiaFusion macOS application. The cell renders plasma physics telemetry (plasma current I_p, toroidal field B_T, electron density n_e) from 9 canonical fusion plant kinds using Apple Metal GPU acceleration. Sovereign time τ is derived from Bitcoin block height, not wall clock.

```
NATS Server (CERN)
    ↓ heartbeat (block_height u64)
GaiaFusion.app (Swift)
    ↓ FFI: gaia_metal_renderer_set_tau()
GaiaFTCL Fusion Cell (Rust/Metal)
    → Renders vQbitPrimitive telemetry with M/T/I/A epistemic colouring
    → Writes ALCOA+ JSON receipts to evidence/
    → Sovereign wallet: gaia1 prefix, mode 0600
```

---

## 3. Functional Requirements

### FR-001 — Nine Canonical Plant Kinds

The system shall recognise and render exactly nine canonical fusion plant kinds. Each plant kind maps to a named USDA OpenUSD scope, defines per-channel telemetry operational windows, and generates a distinct wireframe geometry.

| Plant Kind | USD Scope Name | I_p (MA) | B_T (T) | n_e (×10²⁰ m⁻³) |
|-----------|----------------|----------|---------|-----------------|
| Tokamak | `TokamakPlant` | 0.1–20.0 | 0.5–15.0 | 0.1–5.0 |
| Stellarator | `StellaratorPlant` | 0.0–5.0 | 1.0–10.0 | 0.1–3.0 |
| SphericalTokamak | `SphericalTokamakPlant` | 0.1–5.0 | 0.1–3.0 | 0.5–10.0 |
| FRC (Field-Reversed Config.) | `FRCPlant` | 0.01–1.0 | 0.01–0.5 | 1.0–20.0 |
| Mirror | `MirrorPlant` | 0.001–0.1 | 0.5–20.0 | 0.1–1.0 |
| Spheromak | `SpheromakPlant` | 0.01–0.5 | 0.1–2.0 | 0.1–5.0 |
| ZPinch | `ZPinchPlant` | 0.1–50.0 | 0.0 | 1.0–100.0 |
| MIF (Magnetised Inertial Fusion) | `MIFPlant` | 0.1–10.0 | 1.0–50.0 | 10.0–1000.0 |
| Inertial | `InertialPlant` | 0.0 | 0.0 | 100.0–10000.0 |

**Acceptance criteria:**
- AC-001-1: `parse_usd_string()` correctly maps each of the 9 scope names to its `PlantKind` variant
- AC-001-2: Telemetry values within bounds → rendered with Measured (M) tag
- AC-001-3: Values outside bounds → rejected and epistemic tag set to Assumed (A)
- AC-001-4: Unknown scope name → `vqbit_entropy` = 0.0, `vqbit_truth` = 0.0

---

### FR-002 — OpenUSD Parser

The system shall parse OpenUSD scene description strings containing `def Scope` blocks representing plant telemetry frames. The parser shall handle both multi-line format and compact single-line format.

**Multi-line format (reference):**
```
def Scope "TokamakPlant" {
    custom float vQbit:entropy_delta = 14.2
    custom float vQbit:truth_threshold = 0.87
}
```

**Compact format (also valid):**
```
def Scope "TokamakPlant" { custom float vQbit:entropy_delta = 14.2 custom float vQbit:truth_threshold = 0.87 }
```

**Acceptance criteria:**
- AC-002-1: Both format variants parse correctly to identical `vQbitPrimitive` values
- AC-002-2: Malformed float literal → field defaults to `0.0` (no panic)
- AC-002-3: Missing `vQbit:entropy_delta` → field = `0.0`
- AC-002-4: Empty input → returns empty `Vec<vQbitPrimitive>`
- AC-002-5: Input with no valid `def Scope` blocks → returns empty `Vec<vQbitPrimitive>`

---

### FR-003 — vQbitPrimitive ABI

The system shall define and maintain a stable 76-byte `#[repr(C)]` ABI for the `vQbitPrimitive` struct. Field offsets are locked and may not change without a Major Change Control Record.

```
vQbitPrimitive (76 bytes total, #[repr(C)]):
  offset  0: transform[16×f32] = 64 bytes  — 4×4 transform matrix (row-major)
  offset 64: vqbit_entropy[f32] =  4 bytes  — maps to vQbit:entropy_delta
  offset 68: vqbit_truth[f32]   =  4 bytes  — maps to vQbit:truth_threshold
  offset 72: prim_id[u32]       =  4 bytes  — sequential frame index (0-based)
```

**Acceptance criteria:**
- AC-003-1: `std::mem::size_of::<vQbitPrimitive>() == 76`
- AC-003-2: `offset_of!(vQbitPrimitive, vqbit_entropy) == 64`
- AC-003-3: `offset_of!(vQbitPrimitive, vqbit_truth) == 68`
- AC-003-4: `offset_of!(vQbitPrimitive, prim_id) == 72`
- AC-003-5: Struct is `#[repr(C)]` (verified by `cbindgen` header generation)

---

### FR-004 — Metal GPU Rendering Pipeline

The system shall render `vQbitPrimitive` frames using Apple Metal with a single `MTLRenderPipelineState`. The renderer shall use `MTLLoadActionClear` on every frame (21 CFR Part 11 — no frame persistence).

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Vertex stride | 28 bytes | `GaiaVertex`: position[3×f32=12] + color[4×f32=16] |
| Uniforms size | 64 bytes | MVP matrix[16×f32=64] |
| Pipeline count | 1 | Single epistemic-averaged pipeline |
| Load action | `MTLLoadActionClear` | Mandatory — no cross-frame contamination |
| Pixel format | `BGRA8Unorm` | CAMetalLayer default |
| Default geometry | 8 vertices, 36 indices | Unit cube fallback when no prims loaded |

**Acceptance criteria:**
- AC-004-1: `GaiaVertex` has stride exactly 28 bytes (verified by RG-003 ABI test)
- AC-004-2: `Uniforms` has size exactly 64 bytes (verified by RG-004 ABI test)
- AC-004-3: Renderer creates exactly 1 `MTLRenderPipelineState` object
- AC-004-4: `MTLLoadActionClear` is set on every `MTLRenderPassDescriptor`
- AC-004-5: `gaia_metal_renderer_create()` returns non-null on a Metal-capable device

---

### FR-005 — Epistemic Tag Classification (M/T/I/A)

The system shall classify all telemetry data with one of four epistemic tags. Tags are set at parse time and are read-only thereafter — no runtime mutation.

| Tag | Value | Meaning | Renderer Color |
|-----|-------|---------|---------------|
| Measured (M) | 0 | Live sensor data within calibrated bounds | Blue (high saturation) |
| Tested (T) | 1 | Validated simulation output | Cyan |
| Inferred (I) | 2 | Physics model extrapolation | Green |
| Assumed (A) | 3 | Placeholder or out-of-bounds | Yellow |

**Note:** GAIAFTCL uses 4 epistemic tags (M/T/I/A) because plasma physics evidence distinguishes validated simulation (T) as a category separate from inference (I). This differs intentionally from GaiaHealth (M/I/A, 3 tags). Harmonisation to 3 tags is prohibited.

**Acceptance criteria:**
- AC-005-1: `EpistemicTag` enum has exactly 4 variants: Measured(0), Tested(1), Inferred(2), Assumed(3)
- AC-005-2: No function modifies `epistemic_tag` after `vQbitPrimitive` construction
- AC-005-3: Telemetry within plant bounds → `Measured(0)` assigned
- AC-005-4: Simulation-derived values → `Tested(1)` assigned at source

---

### FR-006 — τ Sovereign Time (Bitcoin Block Height)

The system shall use Bitcoin block height as the canonical time axis (τ). Wall clock time is not used for any physics or validation timestamping. The `TauState` struct provides thread-safe τ storage with NATS heartbeat update.

**TauState design:**
```rust
pub struct TauState {
    block_height: AtomicU64,  // τ — Bitcoin block height
}
```

- `set_tau(height: u64)` — called from NATS heartbeat callback (non-blocking)
- `tau() → u64` — called from Metal render loop (non-blocking)
- If NATS is unreachable: τ remains at last known value (`NATS_UNREACHABLE` is non-fatal)

**Acceptance criteria:**
- AC-006-1: `TauState::new()` initialises `block_height` to 0
- AC-006-2: `set_tau(n)` stores n atomically; `tau()` returns n
- AC-006-3: Concurrent `set_tau` and `tau()` calls do not deadlock or panic
- AC-006-4: FFI functions `gaia_metal_renderer_set_tau()` and `gaia_metal_renderer_get_tau()` delegate to `TauState`
- AC-006-5: NATS unavailable does not panic the render loop

---

### FR-007 — Zero-PII Sovereign Wallet

The system shall provision a sovereign cell identity wallet with zero personally-identifiable information. The wallet file shall be stored with mode 0600.

**Derivation algorithm:**
```
cell_id       = SHA-256(hw_uuid | entropy_bytes | timestamp_ns)
wallet_address = "gaia1" + hex(SHA-256(entropy_bytes | cell_id))[0..38]
wallet_file   = ~/.gaiaftcl/wallet.key (mode 0600)
```

**Acceptance criteria:**
- AC-007-1: Wallet address starts with `gaia1` prefix
- AC-007-2: Wallet file permissions are 0600 (owner read/write only)
- AC-007-3: `pii_stored: false` in IQ receipt
- AC-007-4: No personal information (name, email, IP, device name) in wallet file
- AC-007-5: Re-running IQ does not overwrite existing wallet (idempotent)

---

### FR-008 — Owl Protocol Sovereign Identity

The system shall validate operator identity using secp256k1 compressed public keys (Owl Protocol). Consent expires after 5 minutes.

**Validation rules:**
- Length: exactly 66 hexadecimal characters
- Prefix: `02` or `03` (compressed point prefix)
- Audit log entry: `SHA-256(pubkey)` — never raw pubkey
- Consent window: 300,000 ms (5 minutes)

**Acceptance criteria:**
- AC-008-1: 66-char hex with `02`/`03` prefix → accepted
- AC-008-2: 64-char key → rejected with `InvalidLength`
- AC-008-3: `04` prefix (uncompressed) → rejected
- AC-008-4: Non-hex characters → rejected
- AC-008-5: Audit log stores `SHA-256(pubkey)`, not raw pubkey

---

### FR-009 — 21 CFR Part 11 / EU Annex 11 Compliance (ALCOA+)

The system shall generate ALCOA+-compliant JSON receipts for all qualification phases. Evidence files shall not be overwritten on re-run.

**Required receipt fields:**
```json
{
  "spec":                 "GFTCL-TEST-RUST-001",
  "timestamp":            "<ISO 8601 UTC>",
  "operator_pubkey_hash": "<SHA-256 hex of Owl pubkey>",
  "pii_stored":           false,
  "rust_tests_passed":    32,
  "rust_tests_total":     32,
  "result":               "PASS"
}
```

**Acceptance criteria:**
- AC-009-1: `operator_pubkey_hash` present and non-empty (Attributable)
- AC-009-2: `timestamp` written at execution time, not hardcoded (Contemporaneous)
- AC-009-3: Evidence file not overwritten if already exists (Original)
- AC-009-4: Test count extracted from `cargo test` output, not manually typed (Accurate)
- AC-009-5: `pii_stored: false` present in every receipt

---

### FR-010 — Plant Swap Lifecycle

The system shall manage plant kind transitions through a defined 6-state lifecycle. Entry into REFUSED state is terminal for that swap request.

```
REQUESTED → DRAINING → COMMITTED → VERIFIED → CALORIE  (success)
                                             → CURE      (physics breakthrough)
                     → REFUSED               (validation failure)
```

**REFUSED triggers:**
- Incoming plant kind not in the 9 canonical set
- Telemetry bounds check fails for the incoming plant kind
- τ mismatch > 6 Bitcoin blocks during swap
- WASM boundary check failure (if applicable)

**Acceptance criteria:**
- AC-010-1: Valid plant swap completes REQUESTED → VERIFIED → CALORIE
- AC-010-2: Unknown plant kind → REFUSED (not crash)
- AC-010-3: Out-of-bounds telemetry → REFUSED (not CALORIE)
- AC-010-4: State cannot advance from REFUSED (terminal)

---

### FR-011 — IQ/OQ/PQ Validation Lifecycle

The system shall support a complete GAMP 5 IQ/OQ/PQ validation lifecycle.

**IQ Phase 1 — Hardware & Toolchain:**
- Verify Rust toolchain ≥ 1.75
- Verify Metal-capable GPU (macOS `xcrun metal --version`)
- Verify GAIAFTCL binary compiles clean

**IQ Phase 2 — Sovereign Cell Identity:**
- Generate `~/.gaiaftcl/wallet.key` (zero-PII, mode 0600)
- Write `evidence/iq/iq_receipt.json` (ALCOA+ compliant; legacy mirror at `evidence/iq_receipt.json`)

**OQ — 32 Rust GxP Tests:**

| Series | Count | Description |
|--------|-------|-------------|
| IQ (iq_*) | 2 | Compilation + `#[repr(C)]` verification |
| TP (tp_*) | 10 | Positive path tests |
| TN (tn_*) | 4 | Negative/rejection tests |
| TR (tr_*) | 4 | Regression tests |
| TC (tc_*) | 4 | Concurrency/thread-safety tests |
| TI (ti_*) | 3 | Integration tests |
| RG (rg_*) | 5 | ABI guard tests (field offsets, sizes) |
| **Total** | **32** | |

**PQ — Full Production Cycle:**
- `run_full_cycle.sh`: local build → git push → fresh clone → 32 tests green
- Metal renderer window visible on screen (user-witnessed)
- `evidence/full_cycle_receipt.json` written

**Acceptance criteria:**
- AC-011-1: `cargo test --workspace` passes 32/32 tests
- AC-011-2: `evidence/iq/iq_receipt.json` written with all ALCOA+ fields
- AC-011-3: `evidence/oq/oq_receipt.json` written with `rust_tests_passed: 32`
- AC-011-4: Fresh clone from GitHub passes all 32 tests (PQ phase 4)
- AC-011-5: `evidence/full_cycle_receipt.json` written with `status: FULL_CYCLE_GREEN`

---

## 4. FR → URS Traceability

| FR | URS Reference | Rationale |
|----|--------------|-----------|
| FR-001 | URS §3.1 — Plant Kind Catalogue | 9 canonical plant kinds per CERN physics specification |
| FR-002 | URS §3.2 — Telemetry Ingestion | OpenUSD is the standard scene description format |
| FR-003 | URS §3.3 — Data ABI | ABI stability required for Swift FFI interoperability |
| FR-004 | URS §3.4 — GPU Rendering | Metal mandatory on Apple Silicon; 21 CFR Part 11 frame isolation |
| FR-005 | URS §3.5 — Epistemic Classification | 4-class system required by plasma physics evidence taxonomy |
| FR-006 | URS §3.6 — Sovereign Time | Bitcoin block height as immutable τ substrate |
| FR-007 | URS §4.1 — Zero-PII | GDPR Art. 9, HIPAA §164 (research data) |
| FR-008 | URS §4.2 — Operator Identity | Owl Protocol secp256k1 sovereign identity |
| FR-009 | URS §5.1 — Audit Trail | 21 CFR Part 11 §11.10, EU Annex 11 §9 |
| FR-010 | URS §3.7 — Plant Swap | Operational safety requirement |
| FR-011 | URS §6.1 — Validation Lifecycle | GAMP 5 §8.7–§8.9 IQ/OQ/PQ |

---

## 5. Document Control

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-04-16 | R. Gillespie | Initial approved FS — 11 FRs |

---

*FortressAI Research Institute | Norwich, Connecticut*
*USPTO 19/460,960 | USPTO 19/096,071 | © 2026 All Rights Reserved*
*GAMP 5 Category 5 | FDA 21 CFR Part 11 | EU Annex 11 | CERN Safety*
