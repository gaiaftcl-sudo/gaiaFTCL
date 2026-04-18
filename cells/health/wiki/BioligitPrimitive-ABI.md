# BioligitPrimitive ABI — GaiaHealth Biologit Cell

> **Struct:** `BioligitPrimitive`  
> **Size:** 96 bytes (`#[repr(C)]`)  
> **Crate:** `biologit_usd_parser`  
> **ABI Lock Test:** RG-002 through RG-005  
> **Patents:** USPTO 19/460,960 · USPTO 19/096,071

---

## Overview

`BioligitPrimitive` is the canonical vertex/data type for the GaiaHealth Biologit Cell. It is the biological analog to the `vQbitPrimitive` (76 bytes) of the GaiaFTCL Fusion Cell — but carries molecular dynamics data instead of plasma state.

**Communion note:** Multi-modal S4 projections and C4 ledger settlement still flow through **`vQbit` semantics** (entropy delta / witness) at the envelope layer; see **[GH-S4C4-COMM-001](../docs/S4_C4_COMMUNION_UI_SPEC.md) §0.

Every field in `BioligitPrimitive` is **purely mathematical or physical**. No field carries or can carry personally identifiable information.

---

## Struct Layout (96 bytes, `#[repr(C)]`)

```rust
#[repr(C)]
pub struct BioligitPrimitive {
    // ── Molecular identity ──────────────────────────────── bytes 0–7
    pub molecule_id:    u32,   // Opaque hash — NOT a name or MRN (4 bytes)
    pub residue_index:  u32,   // Residue number in protein chain (4 bytes)

    // ── Spatial position ────────────────────────────────── bytes 8–19
    pub position_x:     f32,   // Å (Angstroms)                   (4 bytes)
    pub position_y:     f32,   // Å                               (4 bytes)
    pub position_z:     f32,   // Å                               (4 bytes)

    // ── Binding thermodynamics ──────────────────────────── bytes 20–27
    pub binding_dg:     f32,   // Binding ΔG (kcal/mol, negative = favorable)
    pub admet_score:    f32,   // ADMET composite 0.0–1.0

    // ── Epistemic classification ─────────────────────────── bytes 28–31
    pub epistemic_tag:  u32,   // 0=Measured, 1=Inferred, 2=Assumed

    // ── Force field context ──────────────────────────────── bytes 32–47
    pub force_field_id: u32,   // 0=Amber, 1=Charmm, 2=Opls, 3=Gromos
    pub temperature_k:  f32,   // Kelvin (250–450 valid)
    pub pressure_bar:   f32,   // bar (0.5–500 valid)
    pub timestep_fs:    f32,   // femtoseconds (0.5–4 valid)

    // ── Simulation metadata ──────────────────────────────── bytes 48–63
    pub sim_time_ns:    f64,   // nanoseconds simulated (≥10 required for CURE)
    pub water_padding_a: f32,  // Å water box padding (≥10 required)
    pub _pad_48_52:     f32,   // Reserved — must be 0.0

    // ── Selectivity ─────────────────────────────────────── bytes 64–71
    pub selectivity_ratio: f64, // Target:off-target selectivity ratio

    // ── Frame / audit ────────────────────────────────────── bytes 72–79
    pub frame_index:    u64,   // MD frame number (0-indexed, wraps at u64::MAX)

    // ── Reserved (future use) ────────────────────────────── bytes 80–95
    pub _reserved_0:    u64,   // Must be 0
    pub _reserved_1:    u64,   // Must be 0
}
```

**Total: 96 bytes. ABI-locked. Any change breaks RG-002–RG-005.**

---

## Field Reference

### Molecular Identity

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `molecule_id` | u32 | 0–3 | SHA-256 truncated hash of PDB ligand entry. Opaque. Never a patient ID or MRN. |
| `residue_index` | u32 | 4–7 | Sequential residue index in protein. Not a personal identifier. |

### Spatial Position

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `position_x` | f32 | 8–11 | X coordinate in Å |
| `position_y` | f32 | 12–15 | Y coordinate in Å |
| `position_z` | f32 | 16–19 | Z coordinate in Å |

### Binding Thermodynamics

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `binding_dg` | f32 | 20–23 | Binding free energy in kcal/mol. Negative = favorable. CURE requires |ΔG| > 0.1. |
| `admet_score` | f32 | 24–27 | Composite ADMET (Absorption, Distribution, Metabolism, Excretion, Toxicity) score. Range: 0.0–1.0. Score < 0.5 → REFUSED. |

### Epistemic Classification

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `epistemic_tag` | u32 | 28–31 | M/I/A epistemic tag: 0=Measured, 1=Inferred, 2=Assumed. Governs Metal render pipeline selection. |

### Force Field Context

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `force_field_id` | u32 | 32–35 | Force field: 0=AMBER, 1=CHARMM, 2=OPLS, 3=GROMOS |
| `temperature_k` | f32 | 36–39 | Simulation temperature in Kelvin. Valid: 250.0–450.0 |
| `pressure_bar` | f32 | 40–43 | Simulation pressure in bar. Valid: 0.5–500.0 |
| `timestep_fs` | f32 | 44–47 | MD timestep in femtoseconds. Valid: 0.5–4.0 |

### Simulation Metadata

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `sim_time_ns` | f64 | 48–55 | Total simulation time in nanoseconds. Must be ≥10.0 for CURE. |
| `water_padding_a` | f32 | 56–59 | Water box padding in Å. Must be ≥10.0. |
| `_pad_48_52` | f32 | 60–63 | Reserved. Always 0.0. |

### Selectivity

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `selectivity_ratio` | f64 | 64–71 | Target IC50 / off-target IC50. Higher = more selective. WASM `selectivity_check` validates this. |

### Frame / Audit

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `frame_index` | u64 | 72–79 | MD frame number for audit trail. Monotonically increasing. |

### Reserved

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| `_reserved_0` | u64 | 80–87 | Must be 0. Future cell extension. |
| `_reserved_1` | u64 | 88–95 | Must be 0. Future cell extension. |

---

## Vertex Color Encoding (Metal)

The `vertex_color()` method encodes the binding and epistemic state into an RGB triplet for the Metal vertex shader:

```rust
pub fn vertex_color(&self) -> [f32; 3] {
    let r = (self.binding_dg.abs() / 20.0).clamp(0.0, 1.0);  // R = binding strength
    let g = self.admet_score.clamp(0.0, 1.0);                  // G = ADMET safety
    let b = match self.epistemic_tag {
        0 => 1.0,  // Measured — full blue (opaque)
        1 => 0.6,  // Inferred — partial blue (60% alpha)
        2 => 0.3,  // Assumed  — minimal blue (30% checkerboard)
        _ => 0.0,
    };
    [r, g, b]
}
```

**Visual semantics:**
- **Bright red** → strong binding (|ΔG| approaching 20 kcal/mol)
- **Bright green** → high ADMET safety score
- **Blue channel** → epistemic confidence (1.0 = Measured, 0.6 = Inferred, 0.3 = Assumed)

---

## Metal Render Pipelines

The `epistemic_tag` field selects which Metal pipeline renders this primitive:

| Tag | Value | Pipeline | MSL Effect |
|-----|-------|----------|-----------|
| Measured | 0 | `m_pipeline` | Opaque (alpha = 1.0) |
| Inferred | 1 | `i_pipeline` | Alpha blend (alpha = 0.6) |
| Assumed | 2 | `a_pipeline` | Checkerboard discard pattern |
| Constitutional Flag | — | `alarm_pipeline` | Pulsing red overlay |

---

## ABI Regression Locks

These tests in `biologit_usd_parser/src/lib.rs` are **permanent ABI guards**. They must pass on every commit. Any field layout change that fails these tests means a breaking ABI change — update the test intentionally and document the migration.

| Test ID | Name | Assertion |
|---------|------|-----------|
| RG-002 | struct_size_is_96_bytes | `size_of::<BioligitPrimitive>() == 96` |
| RG-003 | align_of_is_8_bytes | `align_of::<BioligitPrimitive>() == 8` |
| RG-004 | binding_dg_offset_20 | `offset_of!(BioligitPrimitive, binding_dg) == 20` |
| RG-005 | epistemic_tag_offset_28 | `offset_of!(BioligitPrimitive, epistemic_tag) == 28` |

---

## Comparison with vQbitPrimitive (GaiaFTCL)

| Aspect | `vQbitPrimitive` (Fusion) | `BioligitPrimitive` (Biologit) |
|--------|--------------------------|-------------------------------|
| Size | 76 bytes | 96 bytes |
| Domain | Plasma physics | Molecular dynamics |
| Key field | `tau` (Bitcoin block height) | `binding_dg` (kcal/mol) |
| State field | `plant_kind` (9 values) | `force_field_id` (4 values) |
| Epistemic | `epistemic_tag` u32 | `epistemic_tag` u32 (same encoding) |
| ABI lock tests | RG-001 | RG-002–RG-005 |

---

## Zero-PII Guarantee

The struct contains **no personally identifiable information**:

- `molecule_id` — opaque hash, not a patient identifier
- `residue_index` — protein chain index, not a medical record number
- All numeric fields — physical measurements only
- No string fields
- No timestamp fields linked to persons
- Parser (`parse_pdb()`) strips all PDB AUTHOR/REMARK fields before populating any primitive
