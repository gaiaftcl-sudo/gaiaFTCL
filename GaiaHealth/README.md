# GaiaHealth — Biologit Cell

Sovereign biological computation cell for macOS. Apple Metal · Apple Silicon M-chip unified memory · Zero-PII wallet · GAMP 5 Category 5.

**Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie**

---

## Biological Cell Paradigm

GaiaHealth is the direct biological analog to the GaiaFusion Fusion Cell, operating in the same FoT8D repository. The two cells share wallet infrastructure, GxP qualification tooling, and the Owl Protocol cryptographic identity layer. All cell-type-specific computation — molecular dynamics, protein rendering, ADMET validation — is isolated in this sub-folder.

| Concept | GaiaFusion (Fusion Cell) | GaiaHealth (Biologit Cell) |
|---------|--------------------------|---------------------------|
| Core substrate | Plasma physics | Molecular dynamics |
| Computational unit | Fusion cell | Biological cell |
| Input material | Fuel | Small molecule |
| Interaction event | Fusion event | Binding event (ΔG) |
| Active state | RUNNING | MD simulation active |
| Failure state | TRIPPED | Simulation diverged / ADMET violation |
| Safety alarm | CONSTITUTIONAL_ALARM | Safety boundary crossed |
| Success state | CURE terminal | Validated therapeutic binding |
| Rejection state | REFUSED terminal | Constitutional check failed |
| Physics engine | Metal geometry renderer | MD force field engine |
| Primitive ABI | `vQbitPrimitive` (76 bytes) | `BioligitPrimitive` (96 bytes) |

The foundational equation: **small molecule + protein + MD substrate = CURE**. All three elements are mandatory.

---

## Zero-PII Wallet Mandate

The GaiaHealth wallet contains **zero personally identifiable information**. The wallet file is purely mathematical:

- `cell_id` — SHA-256 hash of hardware UUID + entropy + timestamp
- `wallet_address` — `gaiahealth1` + first 38 hex chars of SHA-256(private_entropy | cell_id)
- `public_key` — secp256k1 compressed public key (hex)

The wallet never contains names, email addresses, dates of birth, medical record numbers, social security numbers, insurance IDs, IP addresses, or any other personal identifiers. It could mathematically belong to any person or no person. Patient identity is maintained solely through the Owl Protocol's cryptographic public key — itself free of personal data.

---

## State Machine (11 States)

```
IDLE → MOORED → PREPARED → RUNNING → ANALYSIS → CURE
                                           └──────→ REFUSED
         └──→ CONSENT_GATE
IDLE ↔ TRAINING
Any → AUDIT_HOLD
RUNNING → CONSTITUTIONAL_FLAG → PREPARED (R3) or IDLE (R2)
```

---

## Workspace Structure

```
GaiaHealth/
├── biologit_md_engine/         # Rust: MD simulation substrate + BioState FFI bridge
│   └── src/
│       ├── lib.rs              # C-callable FFI surface for Swift
│       ├── state_machine.rs    # BiologicalCellState enum + transition guards
│       ├── epistemic.rs        # M/I/A classification spine
│       └── force_field.rs      # AMBER/CHARMM parameter validation
├── biologit_usd_parser/        # Rust: protein/ligand scene parser
│   └── src/
│       ├── lib.rs              # BioligitPrimitive ABI (96 bytes, #[repr(C)])
│       └── parser.rs           # .pdb / .usda scene ingestion
├── gaia-health-renderer/       # Rust: Metal molecular renderer with M/I/A epistemic coloring
│   └── src/
│       ├── lib.rs              # GaiaHealthRendererHandle FFI
│       ├── renderer.rs         # CAMetalLayer + MTLRenderPipeline (objc2-metal)
│       └── shaders.rs          # MSL — M=opaque, I=translucent, A=stippled
├── swift_testrobit/            # Swift: TestRobit for McFusion biologit cell
│   └── Sources/SwiftTestRobit/
│       ├── main.swift                # Harness entry point
│       ├── BioStateTests.swift       # FFI bridge verification
│       ├── StateMachineTests.swift   # State transition guards
│       ├── WalletTests.swift         # Zero-PII wallet — no PHI assertions
│       ├── EpistemicTests.swift      # M/I/A chain completeness
│       └── ConstitutionalTests.swift # WASM 8-export contract tests
├── wasm_constitutional/        # Rust → WASM: 8 deterministic safety exports
│   └── src/lib.rs
├── scripts/
│   ├── iq_install.sh           # IQ + zero-PII sovereign wallet generation
│   ├── oq_validate.sh          # OQ — full automated test suite
│   └── run_full_cycle.sh       # build → test → evidence receipt
├── evidence/                   # GxP receipts (gitignored)
└── wiki/
    └── ZERO_PII_WALLET.md      # Wallet architecture specification
```

---

## Shared Infrastructure (../shared/)

Code shared between GaiaFusion and GaiaHealth lives at `FoT8D/shared/`:

| Crate | Purpose |
|-------|---------|
| `wallet_core` | secp256k1 keypair generation, zero-PII wallet struct |
| `owl_protocol` | Owl identity types, consent state, pubkey operations |
| `gxp_harness` | GxP test series naming, receipt formatting, IQ/OQ/PQ scaffolding |

---

## GxP Test Suite Target

| Series | Count | Coverage |
|--------|-------|---------|
| IQ | 2 | Compilation, `repr(C)` layout |
| TP | 12 | Parsing — protein structures, ligand SMILES, all epistemic tags |
| TN | 5 | Negative — malformed input, constitutional violations, no panic |
| TR | 4 | Type/layout — BioligitPrimitive ABI stride verification |
| TC | 6 | Constitutional — ADMET bounds, PHI boundary, force field |
| TI | 4 | Integration — protein + ligand + MD substrate → CURE pathway |
| RG | 5 | Regression guards — byte-exact ABI locks, zero-PII wallet assertions |
| **Total** | **38** | `cargo test --workspace` |

---

## Requirements

macOS 14 Sonoma or later · Apple Silicon M-chip · Rust stable ≥ 1.85 · Xcode Command Line Tools · wasm-pack (for constitutional substrate)

```zsh
rustup update stable
xcode-select --install
cargo install wasm-pack
```

**First-time install (IQ)** — generates zero-PII sovereign cell identity and wallet. Collects no personal information.

```zsh
zsh scripts/iq_install.sh
```

**Operational Qualification (OQ)**

```zsh
zsh scripts/oq_validate.sh
```
