# IQ — Installation Qualification

Installation Qualification confirms that the hardware, operating system, toolchain, and sovereign cell identity are correctly established before any operational use begins. IQ must be completed and signed before OQ can begin.

**Document reference:** GFTCL-IQ-001
**Framework:** GAMP 5 | EU Annex 11 | FDA 21 CFR Part 11

---

## When to Run IQ

IQ is run **once per machine**, on first install. Re-run IQ if any of the following change:

- The Mac hardware is replaced
- macOS is upgraded to a new major version
- The Rust toolchain is upgraded
- The sovereign cell identity file is lost or corrupted

---

## IQ Prerequisites

| Requirement | Specification | Rationale |
| --- | --- | --- |
| Operating system | macOS 13 Ventura or later | Metal API features required by the renderer |
| CPU | Apple Silicon M-chip | Unified memory architecture; `StorageModeShared` gives zero-copy CPU/GPU access |
| Rust toolchain | stable ≥ 1.85 | `std::mem::offset_of!` stabilised in 1.85; required by GxP layout tests |
| Xcode Command Line Tools | Any current version | Provides `xcrun`, Metal compiler, system frameworks |
| Metal GPU | Present and supported | Confirmed via `system_profiler SPDisplaysDataType` |
| Git | Any version | Required for sovereign cell commit and full-cycle verification |
| OpenSSL | Any version | Required for sovereign wallet key derivation |

---

## Running IQ

```zsh
cd ~/Documents/FoT8D/GAIAFTCL
zsh scripts/iq_install.sh
```

IQ runs in two phases.

**Phase 1 — Hardware and toolchain verification.** The script checks every prerequisite in the table above and prints a PASS or FAIL for each. If any check fails, IQ halts with a non-zero exit code and no identity is created.

**Phase 2 — Sovereign cell identity generation.** On first run, the script derives a cell ID and wallet address from a combination of system UUID, entropy, and timestamp using SHA-256 and secp256k1. The operator is shown the identity and asked to confirm before it is written to disk.

---

## Expected IQ Output

```
  ✅ PASS  macOS version: 15.x (≥ 13 Ventura required)
  ✅ PASS  CPU: Apple Silicon (arm64)
  ✅ PASS  Rust toolchain present
  ✅ PASS  Rust version: 1.85.x (≥ 1.85 required)
  ✅ PASS  Cargo present
  ✅ PASS  Xcode Command Line Tools
  ✅ PASS  Metal GPU: supported
  ✅ PASS  Git present
  ✅ PASS  OpenSSL present

  Sovereign Cell Identity:
    <64-character hex cell ID>
  Wallet Address:
    gaia1<38-character hex>

  Accept? [yes/no]: yes

  ✅ PASS  License accepted
  ✅ PASS  IQ receipt written: evidence/iq/iq_receipt.json
```

---

## IQ Acceptance Criteria

| Check ID | Description | Pass criterion |
| --- | --- | --- |
| IQ-001 | macOS version | ≥ 13.0 Ventura |
| IQ-002 | CPU architecture | arm64 (Apple Silicon) |
| IQ-003 | Rust toolchain present | `rustup show` exits 0 |
| IQ-004 | Rust version | ≥ 1.85.0 |
| IQ-005 | Cargo present | `cargo --version` exits 0 |
| IQ-006 | Xcode CLT | `xcode-select -p` exits 0 |
| IQ-007 | Metal GPU | `system_profiler SPDisplaysDataType` reports Metal supported |
| IQ-008 | Git present | `git --version` exits 0 |
| IQ-009 | OpenSSL present | `openssl version` exits 0 |
| IQ-010 | Sovereign identity created | `evidence/iq/iq_receipt.json` written with cell_id and wallet_address fields |
| IQ-011 | Wallet address format | Starts with `gaia1`, total length 43 characters |
| IQ-012 | Cell ID uniqueness | SHA-256(uuid ‖ entropy ‖ timestamp) — unique per machine per install |

All 12 checks must pass. A single failure halts IQ and blocks OQ.

---

## IQ and the Nine Plant Kinds

IQ verifies the foundational layer that all nine plant kinds depend on. There are no plant-specific IQ steps — the plant kinds are qualified in OQ and PQ. However, IQ establishes the following preconditions that every plant kind requires:

| Precondition | Plant dependency |
| --- | --- |
| Metal GPU confirmed present | All nine plants render via `MTLRenderPipelineState` compiled at startup |
| Apple Silicon M-chip confirmed | `StorageModeShared` unified memory used by all nine plant vertex buffers |
| Rust ≥ 1.85 | `std::mem::offset_of!` used in GxP layout tests for `vQbitPrimitive` ABI (all nine plants) |
| Xcode CLT | Metal Shading Language compiled from embedded source at startup for all nine plant shaders |
| Sovereign identity established | τ (Bitcoin block height) synchronisation requires a unique cell ID |

---

## IQ Evidence

The IQ script writes `evidence/iq/iq_receipt.json` (with a legacy mirror at `evidence/iq_receipt.json`). This file must be present and unmodified before PQ evidence collection begins.

```json
{
  "schema": "GFTCL-IQ-001",
  "timestamp": "2026-04-13T...",
  "cell_id": "<64-char hex>",
  "wallet_address": "gaia1<38-char hex>",
  "checks": {
    "macos_version": "PASS",
    "cpu_arch": "PASS",
    "rust_version": "PASS",
    "cargo": "PASS",
    "xcode_clt": "PASS",
    "metal_gpu": "PASS",
    "git": "PASS",
    "openssl": "PASS",
    "license_accepted": "PASS"
  },
  "result": "IQ_PASS"
}
```

---

## Troubleshooting

**Metal GPU check fails:**
```zsh
system_profiler SPDisplaysDataType | grep -i metal
# Expected: "Metal: Supported"
# If missing: update macOS
```

**Rust version too old:**
```zsh
rustup update stable
rustc --version
```

**Xcode CLT missing:**
```zsh
xcode-select --install
```

**IQ receipt already exists (re-run scenario):**
The script detects an existing receipt and asks whether to regenerate identity. Answer `yes` only if the hardware or identity has genuinely changed. Regenerating identity on the same machine changes the cell ID and requires re-sign of all GxP evidence.
