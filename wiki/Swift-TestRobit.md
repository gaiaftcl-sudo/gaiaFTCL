# GaiaFTCL Swift TestRobit — Fusion Cell OQ Harness

## Document: GFTCL-SWIFT-OQ-001
## Status: SPECIFICATION (harness implementation pending — see CURSOR_BUILD_PLAN.md Task 12)
## Framework: GAMP 5 OQ | FDA 21 CFR Part 11 | EU Annex 11
## Patents: USPTO 19/460,960 | USPTO 19/096,071

---

## Overview

The GAIAFTCL Swift TestRobit is the Swift-layer OQ harness for the GaiaFTCL Fusion Cell. It mirrors the GaiaHealth Swift TestRobit pattern (66 tests, 5 suites) and validates the Rust/Swift FFI boundary that the GaiaFusion macOS application relies on.

The GaiaHealth TestRobit (already built, 66 tests) is the reference implementation. The GAIAFTCL TestRobit follows the same architecture, test series naming, and receipt format.

**Target: 5 suites, ≥30 Swift tests, `evidence/testrobit_receipt.json` (ALCOA+ compliant)**

---

## Architecture

```
GaiaFTCL Swift TestRobit
├── Package.swift                    (Swift Package Manager — .executable target)
├── Sources/GaiaFTCLTestRobit/
│   ├── main.swift                   (harness runner + ALCOA+ receipt writer)
│   ├── TauStateTests.swift          (Suite 1 — τ sovereign time FFI)
│   ├── vQbitABITests.swift          (Suite 2 — vQbitPrimitive ABI + parser)
│   ├── WalletTests.swift            (Suite 3 — zero-PII wallet: gaia1 prefix)
│   ├── OwlProtocolTests.swift       (Suite 4 — Owl identity: 66-char secp256k1)
│   └── RendererFFITests.swift       (Suite 5 — Metal renderer FFI lifecycle)
├── gaia_metal_renderer.h            (cbindgen-generated C header)
└── libgaia_metal_renderer.a         (Rust staticlib — copied from target/release/)
```

---

## Test Suites

### Suite 1 — TauStateTests (target: 10 tests)

Tests the τ (Bitcoin block height) sovereign time FFI bridge.

| Test | Assertion |
|------|-----------|
| tau_001_initial_zero | `gaia_metal_renderer_get_tau(handle) == 0` on create |
| tau_002_set_get_roundtrip | `set_tau(100)` → `get_tau() == 100` |
| tau_003_set_large_height | `set_tau(870_000)` → `get_tau() == 870_000` |
| tau_004_set_zero | `set_tau(0)` → `get_tau() == 0` |
| tau_005_update_increments | Three sequential set_tau calls → latest value returned |
| tau_006_null_handle_set_safe | `set_tau(null, 100)` → no crash |
| tau_007_null_handle_get_safe | `get_tau(null)` → returns 0, no crash |
| tau_008_max_block_height | `set_tau(UInt64.max)` → `get_tau() == UInt64.max` |
| tau_009_create_destroy_lifecycle | create → set_tau → get_tau → destroy → no leak |
| tau_010_multiple_handles_independent | Two handles have independent τ values |

### Suite 2 — vQbitABITests (target: 8 tests)

Tests the `vQbitPrimitive` 76-byte ABI and USD parser behaviour, verified through the Swift/C FFI.

| Test | Assertion |
|------|-----------|
| abi_001_struct_size | `MemoryLayout<vQbitPrimitive>.size == 76` |
| abi_002_entropy_offset | `MemoryLayout<vQbitPrimitive>.offset(of: \.vqbit_entropy) == 64` |
| abi_003_truth_offset | `MemoryLayout<vQbitPrimitive>.offset(of: \.vqbit_truth) == 68` |
| abi_004_prim_id_offset | `MemoryLayout<vQbitPrimitive>.offset(of: \.prim_id) == 72` |
| abi_005_transform_zero_initialised | Default struct: all transform bytes = 0 |
| abi_006_entropy_float_range | `vqbit_entropy` is `Float` (4 bytes, IEEE 754) |
| abi_007_prim_id_u32 | `prim_id` is `UInt32` (4 bytes) |
| abi_008_repr_c_alignment | Struct alignment ≤ 8 bytes (matches `#[repr(C)]`) |

### Suite 3 — WalletTests (target: 8 tests)

Tests the zero-PII sovereign wallet (`gaia1` prefix, mode 0600).

| Test | Assertion |
|------|-----------|
| wallet_001_address_prefix | Address starts with `"gaia1"` |
| wallet_002_address_length | Address length is 43 chars (`gaia1` + 38 hex) |
| wallet_003_file_exists | `~/.gaiaftcl/wallet.key` exists after IQ |
| wallet_004_mode_0600 | File permissions are `0o600` |
| wallet_005_no_pii | File content contains no `@`, SSN, DOB patterns |
| wallet_006_pii_stored_false | `iq_receipt.json` has `"pii_stored": false` |
| wallet_007_deterministic | Same entropy → same wallet address (seeded test) |
| wallet_008_idempotent | Running IQ twice → wallet unchanged, receipt appended |

### Suite 4 — OwlProtocolTests (target: 6 tests)

Tests Owl Protocol secp256k1 identity validation.

| Test | Assertion |
|------|-----------|
| owl_001_66char_02prefix_accepted | `"02" + 64 hex chars` → accepted |
| owl_002_66char_03prefix_accepted | `"03" + 64 hex chars` → accepted |
| owl_003_64char_rejected | 64-char key → `InvalidLength` error |
| owl_004_04prefix_rejected | `"04"` prefix → `InvalidPrefix` error |
| owl_005_nonhex_rejected | Non-hex characters → `InvalidCharacters` error |
| owl_006_audit_log_hashed | Audit entry stores SHA-256 of pubkey, not raw key |

### Suite 5 — RendererFFITests (target: 6 tests)

Tests the Metal renderer FFI lifecycle as used by GaiaFusion.app.

| Test | Assertion |
|------|-----------|
| renderer_001_create_not_null | `gaia_metal_renderer_create()` → non-null handle |
| renderer_002_destroy_idempotent | `destroy()` on valid handle → no crash |
| renderer_003_null_handle_safe | All FFI functions accept null without crashing |
| renderer_004_create_destroy_cycle | 100× create/destroy → no leak (checked by address sanitizer) |
| renderer_005_tau_and_renderer_independent | TauState and renderer handle are orthogonal |
| renderer_006_frame_count_zero | `get_frame_count(handle) == 0` on fresh handle |

---

## Receipt Format (ALCOA+ Required)

Written to `evidence/testrobit_receipt.json` on all-pass:

```json
{
  "spec":                 "GFTCL-SWIFT-OQ-001",
  "cell":                 "GaiaFTCL",
  "gamp_category":        "Category 5",
  "timestamp":            "2026-04-16T18:30:00Z",
  "operator_pubkey_hash": "<SHA-256 of Owl pubkey — not raw key>",
  "pii_stored":           false,
  "training_mode":        true,
  "total_tests":          38,
  "passed":               38,
  "failed":               0,
  "skipped":              0,
  "suites": {
    "TauStateTests":      { "total": 10, "passed": 10 },
    "vQbitABITests":      { "total": 8,  "passed": 8  },
    "WalletTests":        { "total": 8,  "passed": 8  },
    "OwlProtocolTests":   { "total": 6,  "passed": 6  },
    "RendererFFITests":   { "total": 6,  "passed": 6  }
  },
  "status":               "PASS"
}
```

---

## Building the TestRobit

### Prerequisites
- Rust build complete: `cargo build --release --workspace` in GAIAFTCL/
- C header generated: `cbindgen ...` → `gaia_metal_renderer.h`
- Static lib available: `target/release/libgaia_metal_renderer.a`

### Steps
```zsh
cd ~/Documents/FoT8D/GAIAFTCL

# 1. Generate C header
cbindgen --config gaia-metal-renderer/cbindgen.toml \
         --crate gaia-metal-renderer \
         --output gaia_metal_renderer.h

# 2. Copy static lib to TestRobit
cp target/release/libgaia_metal_renderer.a swift_testrobit/

# 3. Build
cd swift_testrobit
swift build

# 4. Run
swift run GaiaFTCLTestRobit
# → writes evidence/testrobit_receipt.json on all-pass
```

---

## Package.swift Template

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GaiaFTCLTestRobit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GaiaFTCLTestRobit",
            path: "Sources/GaiaFTCLTestRobit",
            linkerSettings: [
                .linkedLibrary("gaia_metal_renderer"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .unsafeFlags(["-L.", "-L../target/release"])
            ]
        )
    ]
)
```

---

## Relationship to GaiaHealth TestRobit

| Aspect | GaiaFTCL TestRobit | GaiaHealth TestRobit |
|--------|-------------------|---------------------|
| Target | ≥30 tests, 5 suites | 66 tests, 5 suites (✅ built) |
| Library | `libgaia_metal_renderer.a` | `libbiologit_md_engine.a` |
| Wallet prefix | `gaia1` | `gaiahealth1` |
| State machine | `TauState` (plant swap) | `BioState` (11-state MD) |
| Epistemic tags | M/T/I/A (4 tags) | M/I/A (3 tags) |
| Receipt spec | GFTCL-SWIFT-OQ-001 | GH-SWIFT-OQ-001 |

The two TestRobits share the same ALCOA+ receipt format and the same `SovereignWallet` / `OwlPubkey` test patterns (from shared crates). Suite 3 (WalletTests) and Suite 4 (OwlProtocolTests) are nearly identical except for the `gaia1` vs `gaiahealth1` prefix.

---

*FortressAI Research Institute | Norwich, Connecticut*
*USPTO 19/460,960 | USPTO 19/096,071 | © 2026 All Rights Reserved*
