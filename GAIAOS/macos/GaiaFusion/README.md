# GaiaFusion — Sovereign Fusion Control System

**macOS Native | Metal GPU | Rust FFI | GxP Validated**

[![Build](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/gaiaftcl-sudo/gaiaFTCL/actions)
[![GxP](https://img.shields.io/badge/GxP-GAMP5%20%7C%20EU%20Annex%2011-blue)](evidence/GFTCL-PQ-002_v1.0.md)
[![Patents](https://img.shields.io/badge/patents-USPTO%2019%2F460%2C960%20%7C%2019%2F096%2C071-orange)](LICENSE)

---

## Overview

**GaiaFusion** is the macOS sovereign cell for the GaiaFTCL plasma control mesh. It provides hardware-accelerated 3D visualization of magnetic confinement fusion plant topologies, real-time telemetry ingestion via NATS, and cryptographically-sovereign mesh synchronization — driven by a zero-dependency Rust + Apple Metal rendering stack.

Key properties:

- **Zero OpenUSD dependency** — Rust FFI + Apple Metal replaces all USD rendering bloat
- **Sovereign identity** — Each installation generates a unique secp256k1 wallet address as its cryptographic identity at install time
- **Bitcoin τ synchronization** — Bitcoin block height is the canonical time axis across all 10 mesh cells
- **GxP validated** — Full GAMP 5 / EU Annex 11 / FDA 21 CFR Part 11 IQ → OQ → PQ lifecycle with automated evidence collection
- **CERN-ready** — Designed and validated for deployment on CERN physics lab Macs

---

## Architecture

```
GaiaFusion.app  (Swift / AppKit)
│
├── MetalPlayback/
│   ├── RustMetalProxyRenderer.swift      FFI bridge → Rust static library
│   ├── MetalPlaybackController.swift     Plant lifecycle, τ state, plant swap
│   └── FusionFacilityWireframeGeometry.swift
│
├── Services/
│   ├── NATSService.swift                 Mesh NATS subscriptions, Bitcoin τ
│   └── LocalServer.swift                 Loopback HTTP control API
│
├── Models/
│   ├── OpenUSDLanguageGames.swift        Plant state machine (CALORIE/CURE/REFUSED)
│   └── PlantKindsCatalog.swift           9 canonical fusion topologies
│
└── MetalRenderer/  (Rust workspace)
    ├── rust/src/
    │   ├── ffi.rs        C-callable FFI surface (create/destroy/render/set_tau)
    │   ├── renderer.rs   Metal command encoding, τ field, geometry upload
    │   └── lib.rs        GxP unit tests (tc/tr/ti/tn/rg series)
    ├── include/
    │   └── gaia_metal_renderer.h    cbindgen-generated C header
    └── lib/
        └── libgaia_metal_renderer.a  Static library (built by build_rust.sh)
```

### Rust FFI Surface

Swift calls into Rust via the C header at `MetalRenderer/include/gaia_metal_renderer.h`:

| Function | Description |
|---|---|
| `gaia_metal_renderer_create(layer)` | Create renderer from a borrowed CAMetalLayer pointer |
| `gaia_metal_renderer_destroy(ptr)` | Destroy renderer, free heap memory |
| `gaia_metal_renderer_render_frame(ptr, w, h)` | Encode and submit one Metal render pass |
| `gaia_metal_renderer_set_tau(ptr, block_height)` | Update sovereign time τ (Bitcoin block height) |
| `gaia_metal_renderer_get_tau(ptr)` | Read current τ |
| `gaia_metal_parse_usd(path, buf, max)` | Parse USDA file into vQbitPrimitive buffer |
| `gaia_metal_renderer_upload_primitives(ptr, prims, n)` | Upload parsed geometry to GPU |
| `gaia_metal_renderer_shell_world_matrix(ptr, out16)` | Read current shell world matrix |

### vQbitPrimitive ABI

The ABI boundary between Swift and Rust is `vQbitPrimitive` — a `#[repr(C)]` struct:

| Field | Offset | Type | Description |
|---|---|---|---|
| `transform` | 0 | `[f32; 4][4]` | 4×4 world transform matrix |
| `vqbit_entropy` | 64 | `f32` | Entropy delta ∈ [0, 1] |
| `vqbit_truth` | 68 | `f32` | Truth threshold ∈ [0, 1] |
| `prim_id` | 72 | `u32` | Primitive identifier |

Total size: **76 bytes**. Any change requires PQ re-execution (invariant RG-001).

### Bitcoin τ Flow

```
Bitcoin Core (mainnet)
    │  RPC poll every ~30 seconds
    ▼
bitcoin-heartbeat service  (localhost:8850)
    │  NATS publish → gaiaftcl.bitcoin.heartbeat
    ▼
NATSService.swift
    │  MetalPlaybackController.setTau(blockHeight)
    ▼
RustMetalProxyRenderer.setTau()
    │  gaia_metal_renderer_set_tau(ptr, blockHeight)
    ▼
renderer.rs  →  self.tau: u64  →  Metal render pass
```

---

## Requirements

| Dependency | Minimum | Install |
|---|---|---|
| macOS | 13 Ventura | System update |
| Xcode Command Line Tools | Latest stable | `xcode-select --install` |
| Swift | 6.2+ | Bundled with Xcode |
| Rust | 1.85+ | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Rust target: aarch64-apple-darwin | — | `rustup target add aarch64-apple-darwin` |
| cbindgen | 0.27+ | `cargo install cbindgen` |
| Metal-capable GPU | Apple Silicon or Intel GPU | — |

---

## Quick Start

### 1. Clone

```zsh
git clone https://github.com/gaiaftcl-sudo/gaiaFTCL.git
cd GAIAOS/macos/GaiaFusion
```

### 2. Installation Qualification — run once per machine

The IQ script checks prerequisites, verifies Apple macOS standards (dark mode, accent colour), and generates the **sovereign cell wallet identity**.

```zsh
zsh scripts/iq_install.sh
```

Type `yes` at the licence prompt. Your identity is written to `~/.gaiaftcl/`.

### 3. Build the Rust renderer

```zsh
zsh MetalRenderer/build_rust.sh
```

Produces `MetalRenderer/lib/libgaia_metal_renderer.a` and regenerates the C header via cbindgen.

### 4. Build the Swift app

```zsh
swift build --product GaiaFusion
```

### 5. Operational Qualification — run after every build

```zsh
zsh scripts/oq_validate.sh
```

Verifies the Rust build, runs all GxP tests, checks library size (< 5 MB), and writes `evidence/oq/oq_receipt.json`.

### 6. Run

```zsh
swift run GaiaFusion
# With custom port:
FUSION_UI_PORT=8911 swift run GaiaFusion
```

Or open the Swift package in Xcode → scheme **GaiaFusion** → Run.

---

## GxP Validation Lifecycle

GaiaFusion follows the **GAMP 5 / EU Annex 11 / FDA 21 CFR Part 11** validation lifecycle:

```
IQ — Installation Qualification
     zsh scripts/iq_install.sh
     ✓ System prerequisites (macOS, Rust, Swift, Metal, Xcode CLT, disk, RAM)
     ✓ Apple HIG compliance (dark mode, accent colour detection)
     ✓ Sovereign wallet identity generation (secp256k1)
     ✓ Licence acceptance (wallet as sovereign identity)
     → evidence/iq/iq_receipt.json

OQ — Operational Qualification
     zsh scripts/oq_validate.sh
     ✓ Rust renderer build: debug + release (aarch64-apple-darwin)
     ✓ Static library size < 5 MB (zero-bloat guarantee)
     ✓ C header integrity (set_tau / get_tau present)
     ✓ Full GxP Rust test suite (≥ 14 tests: tc/tr/ti/tn/rg)
     ✓ Swift build + full Swift test suite
     ✓ τ substrate reachability (NATS :4222, heartbeat :8850)
     ✓ Git state (no conflict markers, clean tree)
     → evidence/oq/oq_receipt.json

PQ — Performance Qualification
     zsh scripts/run_full_pq_validation.sh
     ✓ PHY  — Physics Team (PQ-PHY-001 to PQ-PHY-008)  · 8 tests
     ✓ CSE  — Control Systems (PQ-CSE-001 to PQ-CSE-012) · 12 tests
     ✓ QA   — Software QA (PQ-QA-001 to PQ-QA-010)      · 10 tests
     ✓ SAF  — Safety Team (PQ-SAF-001 to PQ-SAF-008)    · 8 tests
     ✓ TAU  — Bitcoin τ Sync (PQ-TAU-001 to PQ-TAU-003) · 3 tests
     → evidence/pq_validation/receipts/master_pq_receipt_*.json
```

Full PQ specification: [`evidence/GFTCL-PQ-002_v1.0.md`](evidence/GFTCL-PQ-002_v1.0.md)

---

## Running Tests

### Rust GxP Tests (headless — no GPU required)

```zsh
cd MetalRenderer/rust
cargo test --target aarch64-apple-darwin
```

Expected output: **14+ tests passing** (tc, tr, ti, tn, rg series).

### Swift Tests

```zsh
swift test
```

> **Note:** Swift tests must be run from **Terminal.app in an interactive macOS desktop session**, not from SSH or a headless context. The XCTest runner requires an active Aqua/WindowServer session. See [Troubleshooting](#troubleshooting) if tests hang.

### Rust + Swift combined (CI-equivalent)

```zsh
zsh scripts/run_full_test_suite.sh
```

Runs Rust tests, Swift build, and writes a structured receipt to `evidence/rust_metal_integration/`.

---

## Sovereign Identity

Each GaiaFusion installation has a unique cryptographic identity created during IQ:

| Component | Value | Location |
|---|---|---|
| Cell ID | SHA256(HW_UUID + entropy + timestamp) | `~/.gaiaftcl/cell_identity` |
| Wallet Address | `gaia1` + secp256k1 public key hash (43 chars) | `~/.gaiaftcl/cell_identity` |
| Wallet Key | secp256k1 private key — **SECRET, mode 600** | `~/.gaiaftcl/wallet.key` |

The wallet address is this cell's **permanent identity** on the sovereign mesh. It is generated exactly once at IQ time. The wallet key must never be committed to git or shared.

---

## Internal HTTP API

While the app is running, a loopback HTTP server is available for operators and automation:

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/fusion/health` | Klein bottle health, WASM surface/runtime, mesh hooks |
| `GET` | `/api/fusion/self-probe` | Full envelope: WASM surface, WASM runtime, cell stack, DOM markers |
| `GET` | `/api/sovereign-mesh` | Native mesh status + `wasm_runtime_closed` |
| `GET` | `/api/fusion/plant-kinds` | 9 canonical plant topologies |
| `POST` | `/api/fusion/swap` | Initiate plant topology swap |

Default port: `8910`. Override with environment variable `FUSION_UI_PORT`.

---

## Plant Topologies

GaiaFusion supports **9 canonical magnetic confinement fusion topologies**:

| # | Topology | Key Feature | I_p Range (MA) | B_T Range (T) |
|---|---|---|---|---|
| 1 | **Tokamak** | Axisymmetric, plasma current, ITER class | 0.5 – 30.0 | 1.0 – 13.0 |
| 2 | **Stellarator** | 3D coils, zero plasma current, no disruptions | 0.0 – 0.2 | 1.5 – 5.0 |
| 3 | **FRC** | Compact, reversed internal field, high-β | 0.1 – 2.0 | 0.0 – 0.1 |
| 4 | **Spheromak** | Self-organised Taylor state, no external coils | 0.05 – 1.0 | 0.0 – 0.5 |
| 5 | **Reversed-Field Pinch** | Reversed edge B_T, dynamo-sustained | 0.5 – 5.0 | 0.1 – 1.5 |
| 6 | **Magnetic Mirror** | Open field lines, high mirror ratio | 0.0 – 0.05 | 1.0 – 10.0 |
| 7 | **Tandem Mirror** | Electrostatic end plugs, ambipolar potential | 0.0 – 0.1 | 1.0 – 15.0 |
| 8 | **Spherical Tokamak** | Low aspect ratio (A < 2), high bootstrap | 0.5 – 10.0 | 0.5 – 3.0 |
| 9 | **MIF / Inertial** | Magnetized inertial fusion | — | — |

Full physics bounds, invariants, and reference facilities: [`docs/PLANT_INVARIANTS.md`](docs/PLANT_INVARIANTS.md)

---

## Mesh Architecture

The sovereign mesh consists of **10 cells** operating in quorum:

- **9 remote cells** — Hetzner + Netcup fleet, WAN-connected
- **1 local cell** — This Mac (GaiaFusion.app, loopback)

| Quorum | System State |
|---|---|
| 10/10 | ✅ Optimal — full mesh features |
| 9/10 | ⚠️ Degraded — one cell offline, functional |
| 8/10 | ⚠️ Warning — reduced redundancy |
| < 8/10 | ❌ SubGame Z fires — telemetry stopped, REFUSED state |

Each cell publishes health to NATS subject `gaiaftcl.fusion.mesh_mooring.v1` and participates in Bitcoin τ synchronisation (±2 block tolerance across all 10 cells).

Verify mesh health and τ synchronisation:

```zsh
zsh scripts/verify_mesh_bitcoin_heartbeat.sh
```

---

## Evidence Package for CERN

The following artifacts are required for CERN regulatory review:

| Artifact | Path | Generator |
|---|---|---|
| IQ Receipt | `evidence/iq/iq_receipt.json` | `iq_install.sh` |
| OQ Receipt | `evidence/oq/oq_receipt.json` | `oq_validate.sh` |
| Master PQ Receipt | `evidence/pq_validation/receipts/master_pq_receipt_*.json` | `run_full_pq_validation.sh` |
| PQ Specification | `evidence/GFTCL-PQ-002_v1.0.md` | Controlled document |
| Rust Test Log | `evidence/rust_metal_integration/rust_tests_output.txt` | `run_full_test_suite.sh` |
| Swift Build Log | `evidence/rust_metal_integration/build_output.txt` | `run_full_test_suite.sh` |
| τ Sync Log | `evidence/pq_validation/tau/tau_synchronization_log.json` | PQ-TAU-001 |
| GitHub Actions Log | GitHub Actions run URL | Auto on push |

---

## Troubleshooting

### `swift test` hangs after "Build complete"

The XCTest runner requires an active **Aqua/WindowServer** session. This is a known macOS constraint — `swiftpm-xctest-helper` parks in uninterruptible sleep (`STAT UE`) when WindowServer is unavailable (headless SSH, IDE agent shell, or after session crash).

**Fix:** Run from Terminal.app in an interactive desktop session. If `STAT UE` helper processes remain after cancelling, **reboot** is the reliable fix — `rm -rf .build` does not clear kernel-parked threads.

### NATS connection failed

```zsh
# Test locally
nc -z -w2 localhost 4222 && echo "NATS OK" || echo "NATS unreachable"

# Establish tunnel to head cell
ssh -L 4222:localhost:4222 -L 8850:localhost:8850 root@77.42.85.60
```

### Rust library missing or stale

```zsh
cd MetalRenderer && zsh build_rust.sh
ls -lh lib/libgaia_metal_renderer.a
# Expected: non-empty .a file
```

### Bitcoin τ not updating

```zsh
curl -s http://localhost:8850/heartbeat
# Expected: {"block_height": 840XXX, "cell_id": "...", "timestamp": "..."}
```

### Metal viewport blank

```zsh
# Verify library
ls -lh MetalRenderer/lib/libgaia_metal_renderer.a

# Check Metal errors in Console.app
log stream --predicate 'process == "GaiaFusion"' --level debug
```

---

## Documentation

| Document | Description |
|---|---|
| [`docs/FUSION_OPERATOR_GUIDE.md`](docs/FUSION_OPERATOR_GUIDE.md) | Operator manual — plant topologies, telemetry, swap protocol, safety interlocks |
| [`docs/PLANT_INVARIANTS.md`](docs/PLANT_INVARIANTS.md) | Physics reference — per-plant parameter bounds, invariants, reference facilities |
| [`evidence/GFTCL-PQ-002_v1.0.md`](evidence/GFTCL-PQ-002_v1.0.md) | GxP PQ master document — 41 test protocols across 5 teams |

---

## Patents

- **USPTO 19/460,960** — GaiaFTCL Sovereign Fusion Control System
- **USPTO 19/096,071** — vQbit Primitive Representation and Metal Rendering Pipeline

© 2026 Richard Gillespie. All rights reserved.

---

*Norwich — S⁴ serves C⁴.*
