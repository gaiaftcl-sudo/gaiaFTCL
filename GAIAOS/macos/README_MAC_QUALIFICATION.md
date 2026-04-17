# Mac App Qualification — Architecture

**Patents:** USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

---

## Overview

Three Mac applications with IQ/OQ/PQ qualification workflow:

| App | Location | Purpose |
|-----|----------|---------|
| **MacFusion** | `GAIAOS/macos/GaiaFusion/` | GAIAFTCL fusion cell — 9 plant kinds, τ Metal renderer |
| **MacHealth** | `GAIAOS/macos/MacHealth/` | GaiaHealth biologit cell — 11-state MD, M/I/A Metal renderer |
| **TestRobot** | `GAIAOS/macos/TestRobot/` | Swift executable for PQ orchestration |

---

## Qualification Phases

### IQ (Installation Qualification) — `.sh` scripts

Verifies:
- Rust staticlibs present (`MetalRenderer/lib/`)
- C headers present (`MetalRenderer/include/`)
- `Package.swift` valid
- App builds successfully
- Executable produced

**Scripts:**
- `GAIAOS/macos/GaiaFusion/scripts/iq_install.sh` → `evidence/iq/macfusion_iq_receipt.json`
- `GAIAOS/macos/MacHealth/scripts/iq_install.sh` → `evidence/iq/machealth_iq_receipt.json`

---

### OQ (Operational Qualification) — `.sh` scripts

Runs fast unit tests only (no long-running tests, no PQ tests):

**MacFusion OQ:**
- 6 test suites: `CellStateTests`, `SwapLifecycleTests`, `PlantKindsCatalogTests`, `FusionFacilityWireframeGeometryTests`, `FusionUiTorsionTests`, `ConfigValidationTests`
- Excludes: `SoftwareQAProtocols` (24h test), `PerformanceProtocols`, `BitcoinTauProtocols`, `UIValidationProtocols`
- Receipt: `evidence/oq/macfusion_oq_receipt.json`

**MacHealth OQ:**
- 5 tests: FFI lifecycle, epistemic round-trip, frame count, null handle safety, out-of-range clamping
- Excludes: Metal PQ test (handled by TestRobot)
- Receipt: `evidence/oq/machealth_oq_receipt.json`

**Scripts:**
- `GAIAOS/macos/GaiaFusion/scripts/oq_validate.sh`
- `GAIAOS/macos/MacHealth/scripts/oq_validate.sh`

---

### PQ (Performance Qualification) — Swift executable

**TestRobot** (`GAIAOS/macos/TestRobot/`) runs Metal GPU offscreen render tests for both apps:

- **MacFusion PQ:** 64×64 offscreen render, Tokamak red (0.9, 0.1, 0.1), verify non-zero pixels
- **MacHealth PQ:** 64×64 offscreen render, Health blue (0.0, 0.4, 0.9), verify non-zero pixels

Writes:
- Individual receipts: `evidence/pq/macfusion_pq_receipt.json`, `evidence/pq/machealth_pq_receipt.json`
- **Unified receipt:** `evidence/TESTROBOT_RECEIPT.json` (overall status, GPU name, all PQ results)

**Build:**
```zsh
cd GAIAOS/macos/TestRobot
swift build
```

**Run:**
```zsh
.build/debug/TestRobot
```

---

## Complete Qualification Flow

### Master Script

Run the complete IQ → OQ → PQ flow for both apps:

```zsh
cd ~/Documents/FoT8D
bash run_full_qualification.sh
```

### What it does:

1. **MacFusion IQ** → Install qualification
2. **MacFusion OQ** → 6 operational tests
3. **MacHealth IQ** → Install qualification
4. **MacHealth OQ** → 5 operational tests
5. **TestRobot PQ** → Metal GPU tests (both apps)
6. **Verify receipts** → 7 JSON receipts present and valid

### Receipts generated:

```
GAIAOS/macos/GaiaFusion/evidence/
├── iq/macfusion_iq_receipt.json
├── oq/macfusion_oq_receipt.json
└── pq/macfusion_pq_receipt.json

GAIAOS/macos/MacHealth/evidence/
├── iq/machealth_iq_receipt.json
├── oq/machealth_oq_receipt.json
└── pq/machealth_pq_receipt.json

evidence/
└── TESTROBOT_RECEIPT.json   ← Unified PQ master receipt
```

---

## Receipt Structure

### IQ Receipt (example: `macfusion_iq_receipt.json`)

```json
{
  "spec": "GFTCL-IQ-MACFUSION-001",
  "phase": "IQ",
  "cell": "MacFusion",
  "timestamp": "2026-04-16T16:52:37Z",
  "checks": {
    "staticlib_present": true,
    "header_present": true,
    "package_manifest": true,
    "build_success": true,
    "executable_present": true
  },
  "iq_status": "PASS",
  "pii_stored": false,
  "operator_pubkey_hash": "REQUIRED"
}
```

### OQ Receipt (example: `macfusion_oq_receipt.json`)

```json
{
  "spec": "GFTCL-OQ-MACFUSION-001",
  "phase": "OQ",
  "cell": "MacFusion",
  "timestamp": "2026-04-16T16:52:40Z",
  "tests_run": 6,
  "tests_passed": 6,
  "tests_failed": 0,
  "tests_skipped": 0,
  "oq_status": "PASS",
  "notes": [
    "Fast unit tests only",
    "Long-running tests excluded",
    "PQ tests run separately by TestRobot"
  ],
  "pii_stored": false,
  "operator_pubkey_hash": "REQUIRED"
}
```

### PQ Receipt (example: `macfusion_pq_receipt.json`)

```json
{
  "spec": "MACFUSION-PQ-001",
  "phase": "PQ",
  "cell": "MacFusion",
  "metal_device_name": "Apple M4 Max",
  "nonzero_pixels": 16384,
  "pq_status": "PASS",
  "timestamp": "2026-04-16T16:52:45Z",
  "pii_stored": false
}
```

### TestRobot Unified Receipt (`TESTROBOT_RECEIPT.json`)

```json
{
  "receipt_id": "TESTROBOT-20260416T165245Z",
  "spec": "FoT8D-TESTROBOT-PQ-001",
  "timestamp": "20260416T165245Z",
  "pii_stored": false,
  "apps": {
    "MacFusion": {
      "pq_status": "PASS",
      "metal_device": "Apple M4 Max",
      "pq_receipt": "/path/to/macfusion_pq_receipt.json"
    },
    "MacHealth": {
      "pq_status": "PASS",
      "metal_device": "Apple M4 Max",
      "pq_receipt": "/path/to/machealth_pq_receipt.json"
    }
  },
  "overall_status": "PASS",
  "notes": [
    "PQ phase only — IQ/OQ handled by zsh scripts",
    "MacFusion Metal PQ: PASS",
    "MacHealth Metal PQ: PASS",
    "GPU: Apple M4 Max"
  ],
  "operator_pubkey_hash": "CELL-OPERATOR-PUBKEY-HASH-REQUIRED"
}
```

---

## Signing the Receipt

After qualification completes, the Cell-Operator must sign `evidence/TESTROBOT_RECEIPT.json`:

1. Compute SHA-256 hash of your Owl secp256k1 public key
2. Replace `"operator_pubkey_hash": "CELL-OPERATOR-PUBKEY-HASH-REQUIRED"` with the hash
3. This constitutes regulatory signature per 21 CFR Part 11 (wallet-moored, non-PII)

---

## STATE: CALORIE Criteria

Qualification achieves `STATE: CALORIE` when:

1. All 7 receipts present and valid JSON
2. `TESTROBOT_RECEIPT.json` shows `"overall_status": "PASS"`
3. Both `MacFusion` and `MacHealth` show `"pq_status": "PASS"`
4. Both apps report valid `metal_device` (not `"NOT_RUN"`, `"MISSING"`, or `"NOT AVAILABLE"`)

---

## Architecture Rationale

### Why separate IQ/OQ/PQ?

- **IQ** (install) → Verifies infrastructure is present before running tests
- **OQ** (operational) → Tests code logic without expensive Metal GPU operations
- **PQ** (performance) → GPU-intensive offscreen renders, requires Metal device

### Why `.sh` for IQ/OQ, Swift for PQ?

- **IQ/OQ:** Simple file checks and unit test orchestration → zsh is sufficient
- **PQ:** Requires Metal API (`MTLDevice`, `MTLCommandQueue`, `MTLTexture`) → Must be Swift

### Why TestRobot instead of extending OQ scripts?

- **Separation of concerns:** PQ is performance/GPU qualification, distinct from operational logic tests
- **Metal API access:** Only Swift can call `MTLCreateSystemDefaultDevice()` and render offscreen
- **Unified receipt:** TestRobot consolidates both apps' PQ results into one master receipt

---

**End of document.**

Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie
