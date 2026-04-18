# GaiaFTCL vQbit Mac Cell — Sovereign Cell Gap Plan
**Spec: GFTCL-GAP-001 | Date: 2026-04-13 | Author: Richard Gillespie**
**Patents: USPTO 19/460,960 | USPTO 19/096,071**

---

## Status Summary

| Phase | Status | Blocking |
|-------|--------|----------|
| IQ Script | ✅ Written | Not yet run end-to-end |
| OQ Script | ✅ Written | Not yet run end-to-end |
| Rust Build (debug + release) | ✅ Passing | — |
| GxP Test Suite (32 tests) | ✅ Passing | — |
| Binary Size < 5 MB | ✅ Verified | — |
| GitHub Actions CI | ✅ Written | Needs push to trigger |
| Git working tree | ⚠️ Dirty | Duplicate files, crates/ |
| τ Integration (Bitcoin block height) | ❌ Gap | FFI bridge required |
| FFI Bridge (staticlib + C header) | ❌ Gap | τ and GaiaFusion wiring |
| NATS subscription (GaiaFusion Swift) | ❌ Gap | Requires FFI bridge |
| Apple HIG compliance | ⚠️ Partial | Dark mode not wired |
| PQ-TAU test series | ❌ Gap | τ not implemented |

---

## Immediate Blockers (Must Resolve Before Push)

### GAP-000-A — Duplicate Files in gaia-metal-renderer/ (USER ACTION REQUIRED)
**Severity: CRITICAL — These will corrupt the build**

macOS Finder created duplicate files during the git rebase conflict. These must be deleted manually.

**Files to delete (in Finder):**
```
GAIAFTCL/gaia-metal-renderer/Cargo 2.toml
GAIAFTCL/gaia-metal-renderer/Cargo 2.lock
GAIAFTCL/gaia-metal-renderer/src/main 2.rs
GAIAFTCL/gaia-metal-renderer/src/renderer 2.rs
GAIAFTCL/gaia-metal-renderer/src/shaders 2.rs
```

**How to delete:**
1. Open Finder → navigate to `GAIAFTCL/gaia-metal-renderer/`
2. Press `Cmd+Shift+.` to show hidden files if needed
3. Select all `* 2.*` files → press Delete
4. Empty Trash

**Verification:**
```zsh
ls gaia-metal-renderer/src/
# Should show ONLY: main.rs  renderer.rs  shaders.rs
```

---

### GAP-000-B — Old crates/ Directory Still Tracked (USER ACTION REQUIRED)
**Severity: HIGH — Creates confusion about project structure**

The old `crates/vqbit_metal_renderer/` and `crates/vqbit_usd_parser/` directories still exist on disk and may be tracked in git.

**Remove from git and disk:**
```zsh
cd ~/Documents/FoT8D/GAIAFTCL
git rm -r --cached crates/ 2>/dev/null || true
rm -rf crates/
git add -A
git commit -m "chore: remove legacy crates/ directory (replaced by gaia-metal-renderer + rust_fusion_usd_parser)"
```

---

## Gap 1 — τ Integration (Bitcoin Block Height as Sovereign Time)

**ID: GAP-TAU-001**
**Priority: HIGH — Required for sovereign cell certification**
**IQ Impact:** OQ Phase 6 currently warns TAU_NOT_IMPLEMENTED
**PQ Impact:** PQ-TAU test series cannot run until this is implemented

### Background
The renderer currently uses `self.frame: u64` incremented each render cycle as its internal time reference. This violates the τ substrate requirement: all GaiaFTCL cells MUST use Bitcoin block height as the canonical time axis.

```
Current (broken):   τ = self.frame (local counter, diverges between cells)
Required:           τ = Bitcoin block height (universal, consensus-time)
```

### Fix: 3-Part Implementation

#### Part 1 — Renderer τ Slot
**File: `gaia-metal-renderer/src/renderer.rs`**

Add `tau: u64` field to `MetalRenderer` struct and a `set_tau()` method:

```rust
pub struct MetalRenderer {
    // ... existing fields ...
    tau: u64,          // ADD: Bitcoin block height (sovereign time)
    frame: u64,        // KEEP: local frame counter for animation smoothing
}

impl MetalRenderer {
    // ADD this method:
    pub fn set_tau(&mut self, block_height: u64) {
        self.tau = block_height;
    }

    fn render_frame(&mut self) {
        // CHANGE: use self.tau for physics-dependent calculations
        // KEEP:   use self.frame for smooth animation interpolation
        self.frame += 1;
    }
}
```

#### Part 2 — FFI Bridge (GAP-FFI-001 — see below)
`set_tau` must be exposed as a C-callable function.

#### Part 3 — NATS Wiring (GAP-NATS-001 — see below)
GaiaFusion Swift must subscribe to `gaiaftcl.bitcoin.heartbeat` and call `set_tau`.

---

## Gap 2 — FFI Bridge (staticlib + C Header)

**ID: GAP-FFI-001**
**Priority: HIGH — Required for τ wiring and GaiaFusion integration**
**Blocks: GAP-TAU-001 Part 2, GAP-NATS-001**

### Current State
`gaia-metal-renderer` is compiled as `[[bin]]` (executable). GaiaFusion Swift cannot call into it.

### Required Changes

#### 2A — Change crate-type in Cargo.toml
**File: `gaia-metal-renderer/Cargo.toml`**

```toml
# CHANGE from:
[[bin]]
name = "gaia-metal-renderer"
path = "src/main.rs"

# TO: add lib alongside bin
[lib]
name = "gaia_metal_renderer"
path = "src/lib.rs"
crate-type = ["staticlib"]

[[bin]]
name = "gaia-metal-renderer"
path = "src/main.rs"
```

#### 2B — Create src/lib.rs
**New file: `gaia-metal-renderer/src/lib.rs`**

```rust
//! GaiaFTCL Metal Renderer — FFI Bridge
//! C-callable interface for GaiaFusion Swift integration

use std::ffi::c_void;

mod renderer;
use renderer::MetalRenderer;

/// Create renderer instance. Returns opaque pointer.
/// Caller owns and must call gaia_metal_renderer_destroy.
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_create() -> *mut c_void {
    match MetalRenderer::new() {
        Ok(r) => Box::into_raw(Box::new(r)) as *mut c_void,
        Err(_) => std::ptr::null_mut(),
    }
}

/// Destroy renderer instance.
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_destroy(ptr: *mut c_void) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr as *mut MetalRenderer)) };
    }
}

/// Render one frame.
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_render_frame(ptr: *mut c_void) {
    if let Some(r) = unsafe { (ptr as *mut MetalRenderer).as_mut() } {
        r.render_frame();
    }
}

/// Set τ (Bitcoin block height). Call on every heartbeat (~every 10 min).
#[no_mangle]
pub extern "C" fn gaia_metal_renderer_set_tau(ptr: *mut c_void, block_height: u64) {
    if let Some(r) = unsafe { (ptr as *mut MetalRenderer).as_mut() } {
        r.set_tau(block_height);
    }
}
```

#### 2C — Generate C Header with cbindgen
**New file: `gaia-metal-renderer/cbindgen.toml`**

```toml
language = "C"
header = "// GaiaFTCL Metal Renderer — Auto-generated C header"
include_guard = "GAIA_METAL_RENDERER_H"
```

**Build command:**
```zsh
cd gaia-metal-renderer
cargo install cbindgen 2>/dev/null || true
cbindgen --config cbindgen.toml --crate gaia_metal_renderer --output gaia_metal_renderer.h
```

**Expected output `gaia_metal_renderer.h`:**
```c
#ifndef GAIA_METAL_RENDERER_H
#define GAIA_METAL_RENDERER_H
#include <stdint.h>
void *gaia_metal_renderer_create(void);
void  gaia_metal_renderer_destroy(void *ptr);
void  gaia_metal_renderer_render_frame(void *ptr);
void  gaia_metal_renderer_set_tau(void *ptr, uint64_t block_height);
#endif
```

---

## Gap 3 — NATS τ Subscription (GaiaFusion Swift)

**ID: GAP-NATS-001**
**Priority: HIGH — Required for cross-cell τ synchronization**
**Depends on: GAP-FFI-001**

### Background
Bitcoin block heights are published by the bitcoin_heartbeat service:
- NATS subject: `gaiaftcl.bitcoin.heartbeat`
- Port: 4222 (NATS), 8850 (heartbeat HTTP)
- Payload: `{ "block_height": 840000, "timestamp": "...", "cell_id": "..." }`
- Frequency: ~every 10 minutes (Bitcoin ~10 min block time)

### Required: GaiaFusion Swift
```swift
// In GaiaFusionApp.swift or appropriate service:
import Foundation

class TauSubscriber {
    let renderer: OpaquePointer  // gaia_metal_renderer_create()

    func start() {
        // Subscribe to NATS gaiaftcl.bitcoin.heartbeat
        // On each message:
        //   let blockHeight = message["block_height"] as! UInt64
        //   gaia_metal_renderer_set_tau(renderer, blockHeight)
    }
}
```

### Verification (OQ Phase 6 will check):
```zsh
# Verify NATS is reachable:
nc -z -w2 localhost 4222 && echo "NATS OK"
# Verify heartbeat service:
nc -z -w2 localhost 8850 && echo "heartbeat OK"
# Verify renderer has set_tau capability:
grep -q "set_tau" gaia-metal-renderer/src/renderer.rs && echo "TAU OK"
```

---

## Gap 4 — Apple HIG Compliance

**ID: GAP-HIG-001**
**Priority: MEDIUM — Required for CERN lab deployment UX**
**Phase detected: IQ-2 (reads system preferences but doesn't wire them)**

### 4A — Dark Mode Support
The IQ script reads `AppleInterfaceStyle` but the renderer doesn't respond to it.

**Add to renderer initialization:**
```rust
// In MetalRenderer::new() or a platform setup function:
// Check NSApp appearance and set Metal clear color accordingly:
// Dark mode:  clear_color = (0.05, 0.05, 0.08, 1.0)  — near-black
// Light mode: clear_color = (0.95, 0.95, 0.98, 1.0)  — near-white
```

**Add to iq_install.sh Phase 2 (verify it already detects):**
```zsh
# Already present — confirms detection works ✅
DARK_MODE=$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo "Light")
```

### 4B — System Accent Color in Renderer
The IQ script reads `AppleAccentColor` but the renderer uses hardcoded colors.

**Add accent color mapping:**
```
-1 = Graphite  → RGB(0.56, 0.56, 0.58)
0  = Red       → RGB(1.0,  0.23, 0.19)
1  = Orange    → RGB(1.0,  0.58, 0.0)
2  = Yellow    → RGB(1.0,  0.8,  0.0)
3  = Green     → RGB(0.2,  0.78, 0.35)
4  = Blue      → RGB(0.0,  0.48, 1.0)   ← default
5  = Purple    → RGB(0.69, 0.32, 0.87)
6  = Pink      → RGB(1.0,  0.18, 0.33)
```

### 4C — Menu Bar Integration
Sovereign cell status visible from macOS menu bar:
- Cell ID (first 8 chars)
- τ (current block height)
- Test status (32/32 ✅)
- Wallet address (first 12 chars)

**Implementation:** NSStatusItem in Swift or via `objc2` in Rust.

---

## Gap 5 — PQ Test Series for τ

**ID: GAP-PQ-TAU-001**
**Priority: MEDIUM — Required for full PQ sign-off**
**Depends on: GAP-TAU-001, GAP-FFI-001**

Add to `evidence/FUSION_PLANT_PQ_PLAN.md`:

### TAU Series (5 tests)

| Test ID | Description | Pass Criterion |
|---------|-------------|----------------|
| TAU-001 | set_tau(0) — genesis block | τ = 0, no crash |
| TAU-002 | set_tau(840000) — halving epoch | τ = 840000, renders correctly |
| TAU-003 | set_tau increments monotonically | τ never decreases between calls |
| TAU-004 | Cross-cell τ tolerance | Two cells within ±2 blocks |
| TAU-005 | τ persists across plant swap | τ preserved through REQUESTED→VERIFIED |

### Wallet Identity Tests (3 tests)

| Test ID | Description | Pass Criterion |
|---------|-------------|----------------|
| WID-001 | cell_id uniqueness | SHA256(uuid|entropy|ts) is unique per cell |
| WID-002 | wallet.key permissions | stat mode = 0600 (owner read only) |
| WID-003 | wallet_address format | Starts with "gaia1", length = 43 chars |

---

## Gap 6 — IQ/OQ End-to-End Verification

**ID: GAP-IQ-001**
**Priority: HIGH — Scripts written but not yet run on Mac hardware**

### Run IQ (first time only — generates sovereign identity):
```zsh
cd ~/Documents/FoT8D/GAIAFTCL
zsh scripts/iq_install.sh
```

**Expected output:**
```
  ✅ PASS  macOS version: 15.x (≥ 13 Ventura required)
  ✅ PASS  CPU: Apple Silicon (arm64) — preferred for Metal
  ✅ PASS  Rust toolchain present
  ✅ PASS  Rust version: 1.85.x (≥ 1.85 required)
  ✅ PASS  Cargo present
  ✅ PASS  Xcode Command Line Tools
  ✅ PASS  Metal GPU: supported
  ✅ PASS  Git present
  ✅ PASS  OpenSSL present
  ...
  Sovereign Cell Identity:
    <64-char hex>
  Wallet Address:
    gaia1<38-char hex>
  Accept? [yes/no]: yes
  ✅ PASS  License accepted
  ✅ PASS  IQ receipt written: evidence/iq_receipt.json
```

**If Metal check fails:**
```zsh
system_profiler SPDisplaysDataType | grep -i metal
# If no output: update macOS or check GPU
```

### Run OQ (every build):
```zsh
zsh scripts/oq_validate.sh
```

**Expected result:** `OPERATIONAL QUALIFICATION COMPLETE` with all 32 tests passing.

**Known warnings (non-blocking):**
- `TAU_NOT_IMPLEMENTED` — renderer uses frame counter (GAP-TAU-001)
- `NATS_UNREACHABLE` — bitcoin heartbeat not running locally (expected for dev)

---

## Gap 7 — Git Hygiene

**ID: GAP-GIT-001**
**Priority: MEDIUM**

Current issues:
1. Duplicate `* 2.*` files staged (see GAP-000-A)
2. `crates/` directory still present (see GAP-000-B)
3. `target/` may still be partially tracked

**Full cleanup sequence:**
```zsh
cd ~/Documents/FoT8D/GAIAFTCL

# 1. Delete duplicates in Finder first (GAP-000-A)

# 2. Remove crates/
git rm -r --cached crates/ 2>/dev/null || true
rm -rf crates/

# 3. Verify .gitignore excludes target
grep -q '\*\*/target/' .gitignore && echo ".gitignore OK"

# 4. Remove any cached target/ entries
git rm -r --cached '**/target/' 2>/dev/null || true

# 5. Commit clean state
git add -A
git status   # verify: only expected files
git commit -m "chore: clean git state — remove duplicates, crates/, cached target/"
git push origin main
```

---

## Execution Sequence (Ordered)

```
PRIORITY ORDER:

BLOCK 0 — Git cleanup (USER + Claude)
  [USER]  Delete * 2.* files in Finder             ← GAP-000-A
  [USER]  Run git cleanup commands above            ← GAP-000-B / GAP-GIT-001

BLOCK 1 — Verify IQ + OQ scripts on hardware
  [USER]  zsh scripts/iq_install.sh                 ← GAP-IQ-001
  [USER]  zsh scripts/oq_validate.sh                ← GAP-IQ-001

BLOCK 2 — τ Implementation (Claude writes code)
  [Claude] Add set_tau() to renderer.rs             ← GAP-TAU-001 Part 1
  [Claude] Create src/lib.rs FFI bridge             ← GAP-FFI-001
  [Claude] Add cbindgen.toml + generate header      ← GAP-FFI-001
  [USER]  cargo build --release (verify staticlib)
  [USER]  Verify gaia_metal_renderer.h generated

BLOCK 3 — GaiaFusion Swift wiring
  [User/Claude] TauSubscriber.swift                 ← GAP-NATS-001
  [USER]  Verify with: nc -z -w2 localhost 4222

BLOCK 4 — Apple HIG
  [Claude] Dark mode clear_color branch             ← GAP-HIG-001 4A
  [Claude] Accent color wire-up                     ← GAP-HIG-001 4B
  [USER]  Toggle System Preferences → verify

BLOCK 5 — PQ Test Series
  [Claude] Add TAU-001..005 to FUSION_PLANT_PQ_PLAN.md ← GAP-PQ-TAU-001
  [Claude] Add WID-001..003 wallet identity tests
  [USER]  Run PQ test suite, collect evidence

BLOCK 6 — CI + CERN Push
  [USER]  git push origin main (triggers GitHub Actions)
  [USER]  Verify Actions green on GitHub
  [USER]  Clone to empty dir, run full cycle        ← run_full_cycle.sh
  [USER]  Archive OQ receipt for CERN evidence package
```

---

## Evidence Package for CERN

Once all gaps are resolved, the following must be present in `evidence/`:

| File | Required | Status |
|------|----------|--------|
| `iq_receipt.json` | ✅ Required | Generated by iq_install.sh |
| `oq_receipt.json` | ✅ Required | Generated by oq_validate.sh |
| `GFTCL-PQ-001_PQ_Specification.docx` | ✅ Required | ✅ Created |
| `FUSION_PLANT_PQ_PLAN.md` | ✅ Required | ✅ Created (TAU series pending) |
| `GAP_PLAN.md` (this file) | ✅ Required | ✅ This document |
| `full_cycle_receipt.json` | ✅ Required | Generated by run_full_cycle.sh |
| `gaia_metal_renderer.h` | ⚠️ Pending | GAP-FFI-001 |
| GitHub Actions run log | ✅ Required | Auto-generated on push |

---

## Open Questions for CERN Physics Team

1. **τ tolerance**: Is ±2 Bitcoin blocks (±20 min) acceptable for plant swap synchronization across mesh cells? Or do we need NTP overlay?

2. **ICF plant**: `n_e ∈ [1e30, 1e32] m⁻³` — confirm these bounds represent pre-ignition through ignition. Post-ignition plasma is different.

3. **Wallet sovereignty**: Is the secp256k1/SHA256 derivation sufficient for CERN's IT security requirements, or does it need FIPS 140-2 compliance?

4. **Binary audit**: Does CERN require a signed binary (Apple Developer ID) for deployment on CERN-managed Macs?

---

*This gap plan is GxP-controlled. Changes require version bump and re-sign.*
*Evidence ID: GFTCL-GAP-001 | Rev: 1.0 | 2026-04-13*
