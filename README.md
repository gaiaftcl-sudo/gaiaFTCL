# vQbit Mac Cell — GaiaFTCL Rust Lean Stack

Sovereign Rust Metal renderer and USD parser for the GaiaFTCL plasma-physics
visualisation platform. Zero C++ dependencies. Direct `objc2-metal` GPU access.

## Architecture

```
GAIAFTCL/
├── rust_fusion_usd_parser/   # vQbitPrimitive USD parser (no openusd dependency)
│   └── src/lib.rs            # 18 GxP tests (IQ/TP/TN)
├── gaia-metal-renderer/      # Metal renderer via objc2-metal 0.3
│   └── src/
│       ├── main.rs           # winit ApplicationHandler entry point
│       ├── renderer.rs       # MetalRenderer + 14 GxP tests (TR/TC/TI/RG)
│       └── shaders.rs        # MSL vertex + fragment shaders (runtime compiled)
└── evidence/                 # Test receipts
```

### vQbitPrimitive ABI (`#[repr(C)]`, 76 bytes)

| Offset | Field          | Type         | USDA attribute                    |
|--------|----------------|--------------|-----------------------------------|
| 0      | transform      | [[f32;4];4]  | —                                 |
| 64     | vqbit_entropy  | f32          | `custom_vQbit:entropy_delta`      |
| 68     | vqbit_truth    | f32          | `custom_vQbit:truth_threshold`    |
| 72     | prim_id        | u32          | —                                 |

## Prerequisites

- macOS 13+ (Apple Silicon or Intel)
- Rust stable ≥ 1.85 (`rustup update stable`)
- Xcode Command Line Tools (`xcode-select --install`)
- GitHub access token with `repo` scope (for push step)

## Quick Start

```bash
# Build
cargo build --release --workspace

# Test
cargo test --workspace

# Run renderer (requires Aqua display session — NOT SSH)
cargo run --release -p gaia-metal-renderer
```

## Full Cycle Test (required for production deployment)

```bash
bash scripts/run_full_cycle.sh
```

This script:
1. Runs the full test suite (`cargo test --workspace`)
2. Builds the release binary (`cargo build --release --workspace`)
3. Commits all changes and pushes to `origin/main`
4. Clones a fresh copy from GitHub into `/tmp/gaiaftcl-verify-YYYYMMDD`
5. Runs the full test suite again on the fresh clone
6. Writes a signed receipt to `evidence/full_cycle_receipt.json`

## GxP Test Coverage

| ID      | Crate          | Description                              |
|---------|----------------|------------------------------------------|
| IQ-001  | parser         | Crate compiles                           |
| IQ-003  | parser         | vQbitPrimitive is 76 bytes               |
| IQ-004  | parser         | Field offsets match ABI spec             |
| TP-001  | parser         | Parse two-prim multi-line USDA           |
| TP-002  | parser         | Empty world returns empty vec            |
| TP-003  | parser         | Scope with no attrs returns zeros        |
| TP-004  | parser         | Missing file returns descriptive error   |
| TP-005  | parser         | Header-only file returns empty vec       |
| TP-006  | parser         | Nine canonical plant prims (one-liner)   |
| TP-007  | parser         | Mixed one-liner + multi-line format      |
| TP-008  | parser         | Extra whitespace around values           |
| TP-009  | parser         | Reversed attribute order                 |
| TP-010  | parser         | prim_id sequence 0..N                    |
| TN-001  | parser         | Malformed float → 0.0, no panic          |
| TN-002  | parser         | No `=` sign → no panic                  |
| TN-003  | parser         | Empty file → empty vec, no panic        |
| TN-004  | parser         | Whitespace-only scope body               |
| TR-001  | renderer       | GaiaVertex is 28 bytes                   |
| TR-002  | renderer       | GaiaVertex field offsets                 |
| TR-003  | renderer       | Uniforms is 64 bytes                     |
| TR-004  | renderer       | vQbitPrimitive importable + default      |
| TC-001  | renderer       | Default geometry: 8 vertices             |
| TC-002  | renderer       | Default geometry: 36 indices             |
| TC-003  | renderer       | All indices within vertex range          |
| TC-004  | renderer       | GaiaVertex::new roundtrip                |
| TI-001  | renderer       | USD prim → vertex color mapping          |
| TI-002  | renderer       | vqbit_entropy clamped above 1.0          |
| TI-003  | renderer       | vqbit_truth clamped below 0.0            |
| RG-001  | renderer       | Vertex stride regression guard           |
| RG-002  | renderer       | Uniforms stride regression guard         |
| RG-003  | renderer       | vQbitPrimitive ABI regression guard      |
| PQ      | renderer       | Metal window launch (user-witnessed)     |

**Automated total: 31 tests** (`cargo test --workspace`)

## Patent

USPTO 19/460,960 · USPTO 19/096,071 — © 2026 Richard Gillespie
