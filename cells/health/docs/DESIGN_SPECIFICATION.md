# Design Specification — GaiaHealth Biologit Cell
## Document ID: GH-DS-001
## Version: 1.0 | Date: 2026-04-16
## Status: DRAFT — PENDING L3 CODE REVIEW
## Owner: Richard Gillespie — FortressAI Research Institute, Norwich CT
## Patents: USPTO 19/460,960 | USPTO 19/096,071
## Framework: GAMP 5 Cat 5 | FDA 21 CFR Part 11 | EU Annex 11

---

## 1. Purpose and Scope

This Design Specification (DS) defines **how** the GaiaHealth Biologit Cell implements the functional requirements stated in GH-FS-001. It is a required GAMP 5 Category 5 lifecycle document positioned between the Functional Specification and Installation Qualification in the V-model. No OQ sign-off is valid without a completed and L3-reviewed DS.

This document describes:
- Module architecture and crate boundaries
- All data structures with field-level layout and offset information
- State machine design and transition validation algorithm
- Epistemic classification design and Metal shader implementation
- FFI bridge design (C-callable surface)
- WASM constitutional substrate design (8 exports)
- Wallet derivation algorithm
- Owl Protocol identity and consent design
- Swift FFI integration and TestRobit harness architecture

**Parent documents:**
- GH-FS-001 — Functional Specification (defines WHAT)
- GH-RTM-001 — Requirements Traceability Matrix (maps FR → test)
- FoT8D-VMP-001 — Validation Master Plan (governs the lifecycle)

---

## 2. System Architecture

### 2.1 Module Boundaries

GaiaHealth is structured as a Rust workspace with four crates plus two shared crates:

```
FoT8D/
├── cells/health/
│   ├── Cargo.toml                     # workspace root
│   ├── biologit_md_engine/            # core: BioState, 11-state machine, M/I/A spine
│   ├── biologit_usd_parser/           # BioligitPrimitive + PDB/SDF/USDA parser
│   ├── gaia-health-renderer/          # Metal renderer FFI + MSL shaders
│   ├── wasm_constitutional/           # 8 WASM constitutional exports
│   └── swift_testrobit/               # Swift GxP OQ harness
└── shared/
    ├── wallet_core/                   # SovereignWallet (shared: Fusion + Biologit)
    └── owl_protocol/                  # OwlPubkey + ConsentRecord (shared)
```

**Dependency graph (direction = depends on):**

```
gaia-health-renderer ──→ biologit_md_engine
biologit_usd_parser  ──→ biologit_md_engine
biologit_md_engine   ──→ shared/owl_protocol
biologit_md_engine   ──→ shared/wallet_core
wasm_constitutional  ──→ (standalone — no workspace deps; communicates via JS bridge)
swift_testrobit      ──→ links .a from biologit_md_engine, gaia-health-renderer
```

**Key design constraint:** `wasm_constitutional` is intentionally isolated — it has no dependency on the Rust state machine. This ensures the WASM sandbox cannot be used to manipulate cell state. Communication is one-directional: Swift calls WASM functions and reads return codes; WASM cannot call back into Rust.

### 2.2 Compilation Targets

| Crate | Target | Output |
|-------|--------|--------|
| `biologit_md_engine` | `aarch64-apple-darwin` | `libbiologit_md_engine.a` |
| `biologit_usd_parser` | `aarch64-apple-darwin` | `libbiologit_usd_parser.a` |
| `gaia-health-renderer` | `aarch64-apple-darwin` | `libgaia_health_renderer.a` |
| `wasm_constitutional` | `wasm32-unknown-unknown` | `gaia_health_substrate_bg.wasm` + `gaia_health_substrate.js` |

Static libraries are linked into the Swift TestRobit executable at build time via Swift Package Manager.

---

## 3. BioligitPrimitive ABI (FR-001, FR-003, FR-009)

### 3.1 Layout

`BioligitPrimitive` is the fundamental data unit uploaded to the Metal GPU vertex buffer. It is the biological analog of `vQbitPrimitive` in GaiaFTCL, extended by 20 bytes to accommodate MD-specific fields.

**Crate:** `biologit_usd_parser/src/lib.rs`

```rust
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct BioligitPrimitive {
    pub transform:     [[f32; 4]; 4],  // offset 0,  64 bytes — model matrix
    pub binding_dg:    f32,            // offset 64,  4 bytes — ΔG kcal/mol
    pub admet_score:   f32,            // offset 68,  4 bytes — ADMET safety [0.0–1.0]
    pub epistemic_tag: u32,            // offset 72,  4 bytes — 0=M, 1=I, 2=A
    pub residue_id:    u32,            // offset 76,  4 bytes — PDB residue sequence
    pub atom_count:    u32,            // offset 80,  4 bytes — atoms in primitive
    pub mol_type:      u32,            // offset 84,  4 bytes — 0=protein,1=ligand,2=water,3=ion
    pub _padding:      [u8; 8],        // offset 88,  8 bytes — alignment
    // Total: 96 bytes
}
```

**Size constant:** `BioligitPrimitive::SIZE = 96`

### 3.2 Vertex Color Encoding

The Metal vertex shader derives color from `binding_dg` and `admet_score`:

| Channel | Source | Formula |
|---------|--------|---------|
| R (red) | `binding_dg` | `clamp(|binding_dg| / 20.0, 0.0, 1.0)` — brighter = stronger binding |
| G (green) | `admet_score` | direct mapping — brighter = safer ADMET |
| B (blue) | `epistemic_tag` | `1.0 - (epistemic_tag as f32 / 3.0)` — brighter = higher confidence |
| A (alpha) | `epistemic_tag` | 1.0 (M), 0.6 (I), 0.3 (A) — controlled by fragment shader |

### 3.3 ABI Regression Locks

Field offsets are locked by GxP regression tests. Any change to the struct layout requires VMP Change Control (Major class) and full re-qualification:

| Test | What is Locked |
|------|---------------|
| RG-002 | `size_of::<BioligitPrimitive>() == 96` |
| RG-003 | `offset_of!(BioligitPrimitive, binding_dg) == 64` |
| RG-004 | `offset_of!(BioligitPrimitive, admet_score) == 68` |
| RG-005 | `offset_of!(BioligitPrimitive, epistemic_tag) == 72` |

---

## 4. State Machine Design (FR-001, FR-002)

### 4.1 BiologicalCellState Enum

**Crate:** `biologit_md_engine/src/state_machine.rs`

```rust
#[repr(u32)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BiologicalCellState {
    Idle              = 0,
    Moored            = 1,
    Prepared          = 2,
    Running           = 3,
    Analysis          = 4,
    Cure              = 5,
    Refused           = 6,
    ConstitutionalFlag = 7,
    ConsentGate       = 8,
    Training          = 9,
    AuditHold         = 10,
}
```

The `#[repr(u32)]` guarantees ABI stability when the discriminant is stored atomically in `BioState.state` (an `AtomicU32`). The Metal renderer reads this value via the `cell_state` uniform.

### 4.2 Transition Validation Algorithm

**Function:** `validate_transition(from: BiologicalCellState, to: BiologicalCellState) -> TransitionResult`

The transition matrix is implemented as a single `match` expression on the pair `(&from, &to)`. This design ensures:
1. The compiler enforces exhaustiveness — no transition can be silently omitted
2. Each allowed transition is explicitly named with a comment explaining the trigger
3. The default arm `_ => false` rejects all unlisted transitions

**Approved transitions implemented in code:**

| From | To | Trigger (comment in source) |
|------|----|-----------------------------|
| Idle | Moored | Researcher-driven forward path |
| Idle | Training | Researcher-driven forward path |
| Moored | Prepared | Researcher-driven forward path |
| Moored | ConsentGate | Consent expiry |
| Prepared | Running | WASM `force_field_bounds_check` must pass |
| Running | Analysis | Automatic on timestep completion |
| Running | ConstitutionalFlag | Automatic WASM alarm |
| Analysis | Cure | Automatic WASM constitutional pass |
| Analysis | Refused | Automatic WASM ADMET/constitutional fail |
| ConstitutionalFlag | Prepared | R3 PI acknowledgement + root cause |
| ConstitutionalFlag | Idle | R2 emergency exit |
| Cure | Prepared | Next lead optimization iteration |
| Refused | Prepared | Modify molecular approach |
| ConsentGate | Moored | Owl re-confirms consent |
| ConsentGate | Idle | Owl withdraws consent |
| Training | Idle | — |
| AuditHold | Idle | R3 clears hold |
| Idle | Idle | Initialization no-op |
| Any | AuditHold | tc_004 — any state may reach AUDIT_HOLD |

**Note:** The FS (GH-FS-001) documents `CONSTITUTIONAL_FLAG → AUDIT_HOLD` as an approved transition. The source code implements the inverse `AUDIT_HOLD → CONSTITUTIONAL_FLAG` from the FS table. The source code represents ground truth for this DS; the FS transition table will be updated in the next revision.

**TransitionResult:**
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransitionResult {
    Allowed,
    Rejected,
}
```

### 4.3 Layout Mode Derivation

Metal opacity and layout mode are derived from state, never the reverse. State drives layout; layout never drives state.

```rust
pub fn forced_layout_mode(&self) -> u32 {
    match self {
        Idle | Moored | Prepared | Cure | Refused
        | Training | ConsentGate | AuditHold   => 0, // .researchFocus
        Running | Analysis                       => 1, // .molecularFocus
        ConstitutionalFlag                       => 2, // .cellAlarm
    }
}
```

| Mode | Value | Metal Opacity | WebView Opacity |
|------|-------|--------------|-----------------|
| `.researchFocus` | 0 | 10% | 100% |
| `.molecularFocus` | 1 | 100% | 0% |
| `.cellAlarm` | 2 | 100% | 85% (locked) |

Researcher layout override is blocked in states: `ConstitutionalFlag`, `ConsentGate`, `AuditHold`.

---

## 5. BioState — Thread-Safe Cell Handle (FR-001, FR-002, FR-006, FR-011)

**Crate:** `biologit_md_engine/src/lib.rs`

### 5.1 Data Structure

```rust
pub struct BioState {
    state:         AtomicU32,         // BiologicalCellState discriminant
    frame_count:   AtomicU64,         // MD simulation frames completed
    epistemic:     AtomicU32,         // EpistemicTag discriminant (0=M, 1=I, 2=A)
    owl_pubkey:    Mutex<Option<String>>, // secp256k1 compressed pubkey; None = IDLE
    training_mode: AtomicU32,         // 0=normal, 1=training (no PHI, no real CURE)
}
```

**Thread-safety design:** Hot-path reads (state, frame_count, epistemic_tag) use atomic operations with `Acquire` ordering. The `owl_pubkey` field uses a `Mutex<Option<String>>` — it is written only once at MOORED transition and cleared at IDLE. This avoids lock contention on the Metal render loop's per-frame reads.

### 5.2 Key Methods

| Method | Behaviour |
|--------|-----------|
| `new()` | Initializes: state=Idle, epistemic=Assumed, training_mode=0 |
| `state()` | `AtomicU32::load(Acquire)` — lock-free |
| `transition(target)` | Calls `validate_transition()`; on Allowed: stores new state; clears owl_pubkey + resets frame_count on Idle |
| `moor_owl(pubkey_hex)` | Validates via `OwlPubkey::from_hex()`; on success stores pubkey and calls `transition(Moored)` |
| `increment_frame()` | `AtomicU64::fetch_add(1, AcqRel)` |
| `set_epistemic(tag)` | `AtomicU32::store(tag as u32, Release)` |

### 5.3 Zero-PII Cleanup at IDLE

When `transition(Idle)` is called, the `BioState` clears its owl_pubkey:
```rust
if target == BiologicalCellState::Idle {
    if let Ok(mut guard) = self.owl_pubkey.lock() {
        *guard = None;   // pubkey is gone; cell has no identity
    }
    self.frame_count.store(0, Ordering::Release);
}
```
This ensures that no cryptographic identity persists in memory after the cell returns to IDLE.

### 5.4 C FFI Surface

`BioState` is exposed to Swift via opaque pointer pattern:

```c
// C-callable API (generated by cbindgen)
void*   bio_state_create(void);
void    bio_state_destroy(void* handle);
uint32_t bio_state_get_state(const void* handle);
uint32_t bio_state_transition(void* handle, uint32_t target_state);
uint32_t bio_state_moor_owl(void* handle, const char* pubkey_hex);
uint32_t bio_state_get_epistemic_tag(const void* handle);
void    bio_state_set_epistemic(void* handle, uint32_t tag);
uint64_t bio_state_get_frame_count(const void* handle);
void    bio_state_increment_frame(void* handle);
uint32_t bio_state_set_training_mode(void* handle, uint32_t enabled);
```

---

## 6. Epistemic Classification Design (FR-003)

**Crate:** `biologit_md_engine/src/epistemic.rs`

### 6.1 EpistemicTag Enum

```rust
#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpistemicTag {
    Measured = 0,   // ITC assays, SPR kinetics, NMR, X-ray crystallography
    Inferred = 1,   // MD simulation ΔG, AutoDock scores, AlphaFold predictions
    Assumed  = 2,   // Literature values, population statistics, reference constants
}
```

**Critical constraint:** There are exactly **3** epistemic tags. `ConstitutionalFlag` is a `BiologicalCellState` (state discriminant = 7), not an epistemic tag. The Metal alarm pipeline is triggered by `cell_state == 7`, not by an epistemic tag value.

### 6.2 Metal Alpha Mapping

| Tag | `metal_alpha_pct()` | Render Effect |
|-----|---------------------|---------------|
| Measured (0) | 100 | Opaque, solid geometric render |
| Inferred (1) | 60 | Translucent, glassy |
| Assumed (2) | 30 | Stippled / checkerboard discard |

### 6.3 Epistemic Chain Validation

```rust
pub fn validate_epistemic_chain(
    input_tag:       EpistemicTag,
    computation_tag: EpistemicTag,
    output_tag:      EpistemicTag,
) -> Result<EpistemicTag, &'static str>
```

**Rules implemented:**
1. **No epistemic upgrade:** Output cannot be more trusted than input. If `output_rank < input_rank` → `Err("EPISTEMIC_UPGRADE_VIOLATION")`.
2. **A-only CURE block:** If both output and computation tags are Assumed → `Err("ASSUMED_BINDING_NOT_VALIDATED")`.
3. **Conservative propagation:** Returns the least-trusted tag in the chain (`max(input_rank, computation_rank, output_rank)`).

### 6.4 CURE Gate

`EpistemicTag::permits_cure()` returns `true` only for Measured and Inferred. This method is called by the state machine before allowing `Analysis → Cure`.

---

## 7. Force Field Validation Design (FR-007)

**Crate:** `biologit_md_engine/src/force_field.rs`

### 7.1 MDParameters

```rust
pub struct MDParameters {
    pub force_field:       ForceField,     // AMBER | CHARMM | OPLS | GROMOS
    pub temperature_k:     f64,            // Kelvin
    pub pressure_bar:      f64,            // bar
    pub timestep_fs:       f64,            // femtoseconds
    pub simulation_ns:     f64,            // nanoseconds
    pub water_padding_ang: f64,            // Ångstroms
}
```

### 7.2 Validation Ranges

| Parameter | Min | Max | Unit | Rationale |
|-----------|-----|-----|------|-----------|
| temperature_k | 250.0 | 450.0 | K | Physiological window (300–310K); extended for in vitro experiments |
| pressure_bar | 0.5 | 500.0 | bar | Standard atmospheric to high-pressure MD |
| timestep_fs | 0.5 | 4.0 | fs | Above 4 fs risks SHAKE constraint failures |
| simulation_ns | 10.0 | ∞ | ns | Minimum for convergent ΔG calculation |
| water_padding_ang | 10.0 | ∞ | Å | Minimum padding to avoid periodic image artifacts |

### 7.3 FFValidationResult

```rust
pub enum FFValidationResult {
    Ok,
    TemperatureOutOfRange   { got: f64, min: f64, max: f64 },
    PressureOutOfRange      { got: f64, min: f64, max: f64 },
    TimestepOutOfRange      { got: f64, min: f64, max: f64 },
    SimulationTooShort      { got: f64, min_ns: f64 },
    WaterPaddingInsufficient { got: f64, min_ang: f64 },
}
```

`to_ffi_code()` maps variants to u32 for C FFI: Ok→0, Temperature→1, Pressure→2, Timestep→3, SimTooShort→4, WaterPadding→5.

---

## 8. Metal Renderer Design (FR-003, FR-010)

**Crate:** `gaia-health-renderer/`

### 8.1 GaiaVertex Layout (MSL)

```metal
struct GaiaHealthVertex {
    float3 position [[attribute(0)]];   // offset 0,  12 bytes
    float4 color    [[attribute(1)]];   // offset 12, 16 bytes
    // float _pad at offset 28, 4 bytes (alignment)
    // Total stride: 32 bytes
};
```

**Regression lock:** RG-006 asserts vertex stride constant == 32. This value is read by Swift to configure the `MTLVertexDescriptor`. Any change requires Major change control.

### 8.2 Uniforms (MSL)

```metal
struct Uniforms {
    float4x4 mvp;              // model-view-projection matrix
    float    epistemic_alpha;  // 1.0=M, 0.6=I, 0.3=A
    uint     epistemic_tag;    // 0=M, 1=I, 2=A
    uint     cell_state;       // BiologicalCellState discriminant
    uint     training_mode;    // 1 = synthetic data
};
```

### 8.3 Four Metal Pipelines

The renderer maintains four `MTLRenderPipelineState` objects. Pipeline selection is driven by `epistemic_tag` and `cell_state`:

| Pipeline | Trigger | Fragment Behaviour |
|----------|---------|-------------------|
| `m_pipeline` | epistemic_tag == 0 (Measured) | Full opacity (alpha=1.0), solid render |
| `i_pipeline` | epistemic_tag == 1 (Inferred) | Blended to 0.6, soft edges |
| `a_pipeline` | epistemic_tag == 2 (Assumed) | alpha=0.3, checkerboard discard pattern |
| `alarm_pipeline` | cell_state == 7 (ConstitutionalFlag) | Pulsing red overlay, overrides epistemic |

### 8.4 MTLLoadActionClear (21 CFR Part 11)

Every render frame MUST issue `MTLLoadActionClear` on the color attachment. This is a regulatory requirement (FR-010) — ghost artifacts from previous frames in audit records would constitute an electronic records integrity violation under 21 CFR Part 11.

The implementation requirement (pending Cursor Task 2):
```swift
let renderPassDescriptor = MTLRenderPassDescriptor()
renderPassDescriptor.colorAttachments[0].loadAction = .clear
renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
```

### 8.5 GaiaHealthRenderer Struct (Rust)

```rust
pub struct GaiaHealthRenderer {
    pub epistemic_tag:  AtomicU32,  // 0=M, 1=I, 2=A
    pub frame_count:    AtomicU64,  // MD playback frame counter
    pub cell_state:     AtomicU32,  // BiologicalCellState discriminant
    pub training_mode:  AtomicU32,  // 0=normal, 1=training
}
```

Metal objects (`MTLDevice`, `MTLCommandQueue`, pipeline state objects) are in `renderer.rs::HealthMetalRenderer` — this struct holds only the atomic fields readable from Swift without lock contention.

### 8.6 C FFI Surface (Renderer)

```c
void*    gaia_health_renderer_create(void);
void     gaia_health_renderer_destroy(void* handle);
void     gaia_health_renderer_set_epistemic_tag(void* handle, uint32_t tag);
void     gaia_health_renderer_set_cell_state(void* handle, uint32_t state);
void     gaia_health_renderer_set_training_mode(void* handle, uint32_t enabled);
uint64_t gaia_health_renderer_get_frame_count(const void* handle);
void     gaia_health_renderer_increment_frame(void* handle);
uint32_t gaia_health_renderer_render_frame(void* handle,
             const void* primitives, uint32_t count);
```

---

## 9. PDB Parser and PHI Scrubbing Design (FR-009)

**Crate:** `biologit_usd_parser/src/parser.rs`

### 9.1 Supported Input Formats

| Format | Extension | Source |
|--------|-----------|--------|
| Protein Data Bank | `.pdb` | Crystallography, cryo-EM; PDB format v3.3 |
| Structure-Data File | `.sdf` | Small molecule (ligand) |
| OpenUSD ASCII | `.usda` | Scene graph (shared with GaiaFusion) |

### 9.2 PHI Scrubbing Algorithm

`parse_pdb()` applies the following filter before any field is parsed:

1. **AUTHOR record stripping:** Any line starting with `AUTHOR` is unconditionally discarded.
2. **REMARK record scanning:** Any line starting with `REMARK` is passed to `contains_phi_pattern()`. If PHI is detected → `ParseError::PhiLeakDetected`. If clean → the line is discarded (all REMARKs stripped).
3. **PHI pattern detection** (`contains_phi_pattern(line: &str) -> bool`):

| Pattern | Regex | PHI Type |
|---------|-------|----------|
| SSN | `\d{3}-\d{2}-\d{4}` | Social Security Number |
| Email | presence of `@` | Email address |
| MRN keyword | `MRN`, `mrn`, `patient` | Medical Record Number |
| Date of birth | `MM/DD/YYYY`, `YYYY-MM-DD` | Date of Birth |
| Phone | `\d{3}[.-]\d{3}[.-]\d{4}` | Phone number |

4. **ATOM/HETATM parsing** proceeds only after the PHI scrub pass completes.

### 9.3 ATOM Record Parsing

PDB column positions (1-indexed, from PDB format v3.3):

| Field | PDB Columns | Rust Slice | Notes |
|-------|-------------|-----------|-------|
| Record type | 1–6 | `line[0..6]` | "ATOM  " or "HETATM" |
| Residue seq | 23–26 | `line[22..26]` | u32 |
| X coordinate | 31–38 | `line[30..38]` | f32, Ångstroms |
| Y coordinate | 39–46 | `line[38..46]` | f32, Ångstroms |
| Z coordinate | 47–54 | `line[46..54]` | f32, Ångstroms |
| Mol type | record | `line[0..6]` | ATOM=protein(0), HETATM=ligand(1) |

Lines shorter than 54 characters are skipped without error.

---

## 10. WASM Constitutional Substrate Design (FR-008)

**Crate:** `wasm_constitutional/src/lib.rs`

### 10.1 Architecture

The WASM module is an **incorruptible governance engine** isolated in WKWebView's WebAssembly linear memory sandbox. It cannot access the Rust state machine, the wallet, or the Metal renderer. Communication is strictly one-directional:

```
Swift layer → calls wasm exports → reads AlarmResult/ADMETResult/etc. → updates cell state via BioState FFI
```

The WASM module has no write path back into Rust. If any export returns a non-zero code, Swift calls `bio_state_transition(handle, CONSTITUTIONAL_FLAG)` via the normal Rust FFI.

### 10.2 Eight Mandatory Exports

| # | Export | Input Types | Return Type | FR |
|---|--------|------------|-------------|-----|
| 1 | `binding_constitutional_check` | `binding_dg: f32, buried_surface_a2: f32` | `AlarmResult` | FR-004, FR-008 |
| 2 | `admet_bounds_check` | `mol_weight_da: f32, log_p: f32, herg_ic50_um: f32, tox_ld50: f32, bioavail_pct: f32` | `ADMETResult` | FR-004, FR-008 |
| 3 | `phi_boundary_check` | `hashed_output: &str` | `PHIResult` | FR-008, FR-009 |
| 4 | `epistemic_chain_validate` | `input_tag: u32, computation_tag: u32, output_tag: u32` | `ChainResult` | FR-003, FR-004 |
| 5 | `consent_validity_check` | `owl_pubkey_hex: &str, granted_at_ms: u64, now_ms: u64` | `ConsentResult` | FR-006, FR-008 |
| 6 | `force_field_bounds_check` | `temperature_k: f32, pressure_bar: f32, timestep_fs: f32, sim_ns: f32` | `FFResult` | FR-007, FR-008 |
| 7 | `selectivity_check` | `target_binding: f32, off_target_binding: f32, herg_ic50_um: f32` | `SelectivityResult` | FR-004, FR-008 |
| 8 | `get_epistemic_tag` | `result_set_type: u32` | `u32` (0=M, 1=I, 2=A) | FR-003, FR-008 |

### 10.3 Result Types

**AlarmResult** (binding_constitutional_check):

| Value | Meaning |
|-------|---------|
| 0 = Pass | Thermodynamically plausible binding event |
| 1 = ImpossibleClash | Steric clash — geometrically impossible |
| 2 = NegativeDGAbsurd | ΔG < −50 kcal/mol — thermodynamically impossible |
| 3 = PositiveDGBound | ΔG > 0 — ligand is not binding |
| 4 = BuriedSurfaceLow | < 300 Ų buried surface area — interaction too weak |

**ADMETResult** (admet_bounds_check):

| Value | Meaning |
|-------|---------|
| 0 = Pass | All ADMET criteria within threshold |
| 1 = HergCardiacRisk | hERG IC50 < 1 µM — cardiac arrhythmia risk |
| 2 = MolWeightHigh | MW > 500 Da — Lipinski Rule of Five violation |
| 3 = LogPOutOfRange | cLogP > 5 or < −2 |
| 4 = ToxicityHigh | Predicted LD50 < 100 mg/kg |
| 5 = BioavailabilityLow | Oral F% < 10 |

**ConsentResult** (consent_validity_check):

| Value | Meaning |
|-------|---------|
| 0 = Valid | Owl identity validated; consent current (< 300,000 ms elapsed) |
| 1 = Expired | > 5 minutes since last consent check |
| 2 = Revoked | Owl identity has revoked consent |
| 3 = InvalidKey | pubkey not a valid secp256k1 compressed key |

### 10.4 Zero-PII in WASM

`phi_boundary_check` receives only **hashed** representations of output data — never raw output strings. The SHA-256 hash is computed in Rust before the value is passed to WASM. This prevents PHI from entering the WASM sandbox even in a compromised WKWebView context.

`consent_validity_check` receives only the secp256k1 hex pubkey and Unix timestamps. No name, email, or DOB is ever passed to WASM.

### 10.5 Build Artifact Location

After `wasm-pack build --target web --release`:

```
wasm_constitutional/pkg/
├── gaia_health_substrate.js         # JS glue (loaded by WKWebView)
├── gaia_health_substrate_bg.wasm    # WASM binary
└── gaia_health_substrate.d.ts       # TypeScript declarations
```

`ConstitutionalTests.swift` checks for `pkg/gaia_health_substrate.js` at startup and SKIPs all 16 constitutional tests if not found, printing the build command.

---

## 11. Sovereign Wallet Design (FR-005)

**Crate:** `shared/wallet_core/src/lib.rs`

### 11.1 CellType Enum

```rust
pub enum CellType {
    Fusion,    // GaiaFTCL — wallet_prefix() = "gaia1"
    Biologit,  // GaiaHealth — wallet_prefix() = "gaiahealth1"
}
```

### 11.2 SovereignWallet Structure

```rust
pub struct SovereignWallet {
    pub cell_id:         String,   // SHA-256(hw_uuid | entropy | timestamp)
    pub wallet_address:  String,   // "gaiahealth1" + hex(SHA-256(entropy|cell_id))[0..38]
    pub private_entropy: String,   // 32-byte random hex (from openssl rand -hex 32)
    pub cell_type:       CellType,
    pub generated_at:    String,   // UTC ISO 8601 — not linked to any person
}
```

### 11.3 Derivation Algorithm

`SovereignWallet::derive(hw_uuid, entropy, timestamp, cell_type)`:

```
1. cell_id = SHA-256( hw_uuid | "|" | entropy | "|" | timestamp )  [hex string]
2. private_entropy = entropy  [pass-through — already 32 random bytes]
3. addr_hash = SHA-256( private_entropy | "|" | cell_id )  [hex string]
4. wallet_address = cell_type.wallet_prefix() + addr_hash[0..38]
   → "gaiahealth1" + first 38 chars of addr_hash
```

**Inputs:**
- `hw_uuid`: Hardware UUID from `ioreg -d2 -c IOPlatformExpertDevice | grep UUID` — an anonymous hardware identifier, not linked to a person
- `entropy`: 32 bytes from `openssl rand -hex 32` — cryptographically random
- `timestamp`: UTC ISO 8601 at generation time

No personal information is accepted as input. The function signature enforces this at the type level — it accepts only `&str` values for the mathematical inputs.

### 11.4 Zero-PII Enforcement (6 Layers)

| Layer | Mechanism |
|-------|-----------|
| 1. Type signature | `derive()` accepts no personal fields — no name, email, DOB parameter exists |
| 2. JSON schema | Wallet JSON contains only: cell_id, wallet_address, private_entropy, generated_at, pii_stored |
| 3. Machine assertion | `"pii_stored": false` is a required field with required value |
| 4. File permissions | Wallet written as mode 0600 (owner read-only) by `iq_install.sh` Phase 3 |
| 5. TN test | `Wallet-TN-001`: 14 PHI regex patterns asserted absent from entire wallet JSON |
| 6. WASM scan | `phi_boundary_check()` scans all CURE output strings for PHI patterns |

### 11.5 JSON Output Format

```json
{
  "schema_version": "1.0",
  "cell_type": "biologit",
  "cell_id": "<64-char hex>",
  "wallet_address": "gaiahealth1<38-char hex>",
  "private_entropy": "<64-char hex>",
  "generated_at": "<ISO 8601 UTC>",
  "pii_stored": false,
  "gamp_category": 5
}
```

---

## 12. Owl Protocol Design (FR-006)

**Crate:** `shared/owl_protocol/src/lib.rs`

### 12.1 OwlPubkey

```rust
pub struct OwlPubkey(pub String);
```

**Validation** (`from_hex(s: &str) -> Result<Self, OwlError>`):
1. Length must be exactly 66 characters → else `InvalidLength`
2. All characters must be ASCII hexadecimal → else `NotHex`
3. Must start with "02" or "03" (secp256k1 compressed point prefix) → else `InvalidPrefix`

These three rules collectively ensure only legitimate secp256k1 compressed public keys are accepted. Email addresses (contain `@`), names (contain non-hex characters), SSNs (too short, non-hex characters), and all other personal identifiers fail at rule 2 or rule 1.

**Audit logging:** `chain_hash()` returns `hex(SHA-256(pubkey))`. This hash — never the raw pubkey — is used in all audit log entries. A hash of a public key cannot be reversed to identify a person.

**`short_id()`** returns the first 8 characters of the hex pubkey — safe for debug logs (statistically non-linkable to a person given the space of secp256k1 pubkeys).

### 12.2 ConsentRecord

```rust
pub struct ConsentRecord {
    pub owl_pubkey:     OwlPubkey,   // cryptographic identity — no PII
    pub granted_at_ms:  u64,         // Unix timestamp in milliseconds
    pub state:          ConsentState, // Valid | Expired | Revoked
}
```

**Consent validity:** `is_valid(now_ms: u64) -> bool`:
```
now_ms - granted_at_ms < 300_000   (5 minutes = 300,000 ms)
AND state == ConsentState::Valid
```

This 5-minute window matches the WASM `consent_validity_check` export. Both the native Rust implementation and the WASM implementation apply the same 300,000 ms threshold — the WASM acts as an independent cross-check.

### 12.3 OwlError Variants

```rust
pub enum OwlError {
    InvalidLength { got: usize, expected: usize },
    NotHex,
    InvalidPrefix,
}
```

When `bio_state_moor_owl()` receives an invalid pubkey, it calls `transition(Refused)` (not a panic). The fault code is logged using `OwlError`'s debug representation. The REFUSED state permits recovery to PREPARED once the operator provides a valid pubkey.

---

## 13. Swift TestRobit Architecture (FR-011)

**Crate:** `swift_testrobit/Sources/SwiftTestRobit/`

### 13.1 Design

The Swift TestRobit is the GAMP 5 OQ harness. It runs entirely in `training_mode = true`, calling the Rust FFI bridge via the static libraries (`.a` files) and the WASM exports via a lightweight JavaScript engine.

### 13.2 Five Test Suites

| Suite | Test Count | Series | Primary FR |
|-------|-----------|--------|-----------|
| BioStateTests | 12 | IQ, TP, TN, RG | FR-001, FR-002, FR-006, FR-011 |
| StateMachineTests | 10 | TP, TN, TC | FR-001, FR-002, FR-004 |
| WalletTests | 10 | IQ, TP, TN, RG | FR-005, FR-006 |
| EpistemicTests | 10 | TP, TC, RG | FR-003, FR-004 |
| ConstitutionalTests | 16 | TC | FR-004, FR-007, FR-008, FR-009 |
| **Total** | **58** | | |

### 13.3 WASM Execution Model

ConstitutionalTests.swift checks for the WASM module at startup:

```swift
let wasmPath = "wasm_constitutional/pkg/gaia_health_substrate.js"
guard FileManager.default.fileExists(atPath: wasmPath) else {
    print("SKIP: WASM module not found. Run: wasm-pack build --target web --release")
    return
}
```

If the module is missing, all 16 ConstitutionalTests SKIP. OQ cannot pass with any SKIP.

### 13.4 Evidence Receipt

On all-pass completion, TestRobit writes:

```json
{
  "phase": "OQ",
  "cell": "GaiaHealth-Biologit",
  "gamp_category": 5,
  "timestamp": "<ISO 8601 UTC>",
  "operator_pubkey_hash": "<SHA-256 of owl pubkey — not the raw pubkey>",
  "pii_stored": false,
  "training_mode": true,
  "total_tests": 58,
  "passed": 58,
  "failed": 0,
  "skipped": 0,
  "status": "PASS",
  "suites": {
    "BioStateTests":       { "passed": 12, "failed": 0 },
    "StateMachineTests":   { "passed": 10, "failed": 0 },
    "WalletTests":         { "passed": 10, "failed": 0 },
    "EpistemicTests":      { "passed": 10, "failed": 0 },
    "ConstitutionalTests": { "passed": 16, "failed": 0 }
  }
}
```

Receipt path: `cells/health/evidence/testrobit_receipt.json`

The receipt is **never** written if any test fails or SKIPs. Partial receipts are not permitted (ALCOA+ Original principle).

### 13.5 IQ Receipt

Written by `cells/health/scripts/iq_install.sh` at end of Phase 7:

```json
{
  "phase": "IQ",
  "cell": "GaiaHealth-Biologit",
  "gamp_category": 5,
  "timestamp": "<ISO 8601 UTC>",
  "operator_pubkey_hash": "<SHA-256 of owl pubkey>",
  "pii_stored": false,
  "rust_tests_passed": 38,
  "wallet_provisioned": true,
  "status": "PASS"
}
```

---

## 14. IQ Installation Script Design (FR-005, FR-006)

**File:** `cells/health/scripts/iq_install.sh`

### 14.1 Seven Phases

| Phase | Activity | GxP Exit Criteria |
|-------|----------|-------------------|
| 1 | Prerequisite check: rustc ≥ 1.75, swift ≥ 5.9, wasm-pack, cbindgen, Xcode CLT ≥ 15 | All tools present |
| 2 | `cargo build --release` | Exit code 0; `.a` files produced |
| 3 | Wallet provisioning | `wallet.key` created at mode 0600; `gaiahealth1` prefix validated |
| 4 | Header generation via cbindgen | `.h` files produced |
| 5 | WASM build via wasm-pack | `pkg/` directory produced |
| 6 | `cargo test` — all 38 Rust GxP tests | 38 passed, 0 failed |
| 7 | IQ receipt write | `evidence/iq_receipt.json` written; ALCOA+ fields populated |

### 14.2 Wallet Provisioning (Phase 3)

```bash
HW_UUID=$(ioreg -d2 -c IOPlatformExpertDevice | grep UUID | awk '{print $NF}' | tr -d '"')
ENTROPY=$(openssl rand -hex 32)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# → derives wallet via SovereignWallet::derive() (called via a small Rust binary)
# → writes wallet.json to ~/.gaiahealth/wallet.key
# → chmod 600 ~/.gaiahealth/wallet.key
```

No personal information enters Phase 3.

---

## 15. Shared Infrastructure Design

### 15.1 shared/wallet_core

- Used by: GaiaFTCL (CellType::Fusion, prefix "gaia1") and GaiaHealth (CellType::Biologit, prefix "gaiahealth1")
- Change impact: Any change to `SovereignWallet` or `CellType` triggers re-validation of both cells
- Current GxP test: `wallet_json_has_no_personal_fields` (Rust unit test in wallet_core)

### 15.2 shared/owl_protocol

- Used by: Both cells for Owl identity validation and consent management
- Change impact: Changes to `OwlPubkey::from_hex()` validation rules or `ConsentRecord::is_valid()` window affect both cells
- Current GxP tests: `tp_002_moor_owl_accepts_valid_pubkey`, `tn_001_moor_owl_rejects_email`, `tn_002_moor_owl_rejects_name`, `consent_expires_after_5_minutes`

### 15.3 shared/gxp_harness

- Status: Empty stub — `GxpTestSuite` trait and `ValidationOrchestrator` not yet implemented
- Current use: Both cells reference the crate but implement test harnesses independently (Swift TestRobit for GaiaHealth; Rust integration tests for GaiaFTCL)
- Future: Implement unified harness per VMP Section 6

---

## 16. Known Implementation Gaps (Cursor Build Plan Tasks)

The following implementation gaps are documented for the Cursor agent (CURSOR_BUILD_PLAN.md) and the L3 reviewer:

| Gap | Location | Task | Impact |
|-----|----------|------|--------|
| renderer.rs Metal stub | `gaia-health-renderer/src/renderer.rs` | Task 2 | `HealthMetalRenderer::new()` and `render_frame()` not yet implemented; 4 MTLRenderPipelineState objects required |
| Workspace linkage | `cells/health/Cargo.toml` | Task 1 | `shared/wallet_core` and `shared/owl_protocol` not yet in workspace members |
| cbindgen.toml missing | `biologit_md_engine/`, `gaia-health-renderer/` | Task 3 | C headers not yet generated |
| WASM not built | `wasm_constitutional/pkg/` | Task 4 | `ConstitutionalTests` will SKIP until `wasm-pack build` is run |
| `biologit_usd_parser` dep | `cells/health/Cargo.toml` | Task 1 | Missing dependency on `biologit_md_engine` |
| `memoffset` crate | `biologit_usd_parser/Cargo.toml` | Task 1 | `offset_of!` macro requires `memoffset = "0.9"` dev-dependency |

These gaps do not affect the architectural validity of this DS — they are implementation completions documented in the build plan.

---

## 17. Traceability to Functional Specification

| FR | DS Section | Implementation Location |
|----|------------|------------------------|
| FR-001 (11 states) | §4.1 | `state_machine.rs::BiologicalCellState` |
| FR-002 (transitions) | §4.2 | `state_machine.rs::validate_transition()` |
| FR-003 (epistemic) | §6 | `epistemic.rs::EpistemicTag`, §8.3 shaders |
| FR-004 (CURE conditions) | §6.4, §10.2 | `epistemic.rs::permits_cure()`, 8 WASM exports |
| FR-005 (zero-PII wallet) | §11 | `wallet_core/src/lib.rs::SovereignWallet` |
| FR-006 (Owl identity) | §12 | `owl_protocol/src/lib.rs::OwlPubkey` |
| FR-007 (force field) | §7 | `force_field.rs::validate_ff_parameters()` |
| FR-008 (WASM exports) | §10 | `wasm_constitutional/src/lib.rs` (8 exports) |
| FR-009 (PHI scrubbing) | §9 | `biologit_usd_parser/src/parser.rs::parse_pdb()` |
| FR-010 (21 CFR Pt 11) | §8.4 | renderer.rs `MTLLoadActionClear`; audit log SHA-256 hash |
| FR-011 (training mode) | §13 | `BioState::training_mode`, TestRobit receipt |
| FR-012 (PQ ΔG target) | — | Execution protocol in `wiki/PQ-Performance-Qualification.md` |

---

## 18. L3 Code Review Scope

The L3 Reviewer SHALL review the following against this DS:

1. `biologit_md_engine/src/state_machine.rs` — transition matrix completeness and correctness (§4.2)
2. `biologit_md_engine/src/epistemic.rs` — chain validation logic, no fourth epistemic tag (§6.3)
3. `biologit_md_engine/src/lib.rs` — `BioState` zero-PII cleanup at IDLE (§5.3)
4. `biologit_usd_parser/src/lib.rs` — `BioligitPrimitive` field offsets match §3.1
5. `biologit_usd_parser/src/parser.rs` — PHI scrub algorithm matches §9.2
6. `shared/wallet_core/src/lib.rs` — derivation algorithm matches §11.3
7. `shared/owl_protocol/src/lib.rs` — 66-char/02-03-prefix validation matches §12.1
8. `wasm_constitutional/src/lib.rs` — all 8 exports present and return types match §10.2
9. `gaia-health-renderer/src/shaders.rs` — vertex stride = 32, Uniforms layout matches §8.2
10. `gaia-health-renderer/src/renderer.rs` — MTLLoadActionClear implementation (§8.4) [pending Task 2]

**L3 Reviewer sign-off is required before IQ can be signed off.**

---

## 19. Document Control

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-04-16 | R. Gillespie | Initial DS — derived from source code audit; all 12 FRs traced |

**Status:** DRAFT — requires L3 Code Review and counter-signature before APPROVED status.

**Next action:** Appoint L3 Reviewer; schedule code review session against §18 scope.

---

*FortressAI Research Institute | Norwich, Connecticut*
*USPTO 19/460,960 | USPTO 19/096,071 | © 2026 All Rights Reserved*
