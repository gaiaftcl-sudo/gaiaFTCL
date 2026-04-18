# Mac App Qualification — Architecture

**Patents:** USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

---

## Overview

Three Mac applications with IQ/OQ/PQ qualification workflow:

| App | Location | Purpose |
|-----|----------|---------|
| **MacFusion** | `cells/fusion/macos/GaiaFusion/` | GAIAFTCL fusion cell — 9 plant kinds, τ Metal renderer |
| **MacHealth** | `cells/fusion/macos/MacHealth/` | GaiaHealth biologit cell — 11-state MD, M/I/A Metal renderer |
| **GaiaFTCL Console** | `cells/fusion/macos/GaiaFTCLConsole/` | Terminal-only operator shell — launches cells via `Process`, NATS read-only, **no** GaiaFusion/MacHealth SPM deps ([`LOCKED.md`](GaiaFTCLConsole/LOCKED.md)) |
| **TestRobot** | `cells/fusion/macos/TestRobot/` | Swift executable for PQ orchestration |

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
- `cells/fusion/macos/GaiaFusion/scripts/iq_install.sh` → `evidence/iq/macfusion_iq_receipt.json`
- `cells/fusion/macos/MacHealth/scripts/iq_install.sh` → `evidence/iq/machealth_iq_receipt.json`
- `cells/fusion/macos/GaiaFTCLConsole/scripts/iq_install.sh` → `evidence/iq/gaiaftclconsole_<timestamp>.json`

---

### OQ (Operational Qualification) — `.sh` scripts

Runs fast unit tests only (no long-running tests, no PQ tests):

**MacFusion OQ:**
- 6 test suites: `CellStateTests`, `SwapLifecycleTests`, `PlantKindsCatalogTests`, `FusionFacilityWireframeGeometryTests`, `FusionUiTorsionTests`, `ConfigValidationTests`
- Excludes: `SoftwareQAProtocols` (24h test), `PerformanceProtocols`, `BitcoinTauProtocols`, `UIValidationProtocols`
- Receipt: `evidence/oq/macfusion_oq_receipt.json`

**MacHealth OQ:**
- **SIL V2 clinical protocol (seven scenarios):** XCTest in `macos/MacHealth/Tests/SILV2/` validates §0 cross-cutting rails, §10 receipt-schema blocks, and per-scenario physics thresholds from the canonical report [`Scenarios_Physics_Frequencies_Assertions.md`](../../Scenarios_Physics_Frequencies_Assertions.md) (repo root). **MSL** = Mesenchymal Stem-Like TNBC (not Madelung's). Scenarios: inv(3) AML, Parkinson’s THz, MSL TNBC, breast (general THz), colon, lung, skin (BCC/melanoma). Golden OQ fixture: `evidence/oq/sil_v2_unit_protocol_contract_fixture.json` (`validation_tier: SIL_protocol_contract`). **CI:** repo-root [`.github/workflows/mac-cell-ci.yml`](../../.github/workflows/mac-cell-ci.yml) runs **MacHealth — SIL V2 swift test** (and GaiaFusion build/test). See [`MAC_HEALTH_SIL_V2_WIKI_DRAFT.md`](MAC_HEALTH_SIL_V2_WIKI_DRAFT.md) for a GitHub Wiki–ready matrix.
- Renderer / wire tests: FFI lifecycle, epistemic round-trip, frame count, null handle safety, out-of-range clamping; ZMQ header; telemetry SIL tick `(M_SIL)`; GAMP5 games narrative (**narrative contract tier only**, not live validation).
- Metal PQ offscreen test remains in `MacHealthTests`; headed PQ orchestration may also use TestRobot.
- Receipt: `evidence/oq/machealth_oq_receipt.json` (legacy); SIL contract tier is validated by tests above (no PHI).

**Scripts:**
- `cells/fusion/macos/GaiaFusion/scripts/oq_validate.sh`
- `cells/fusion/macos/MacHealth/scripts/oq_validate.sh`
- `cells/fusion/macos/GaiaFTCLConsole/scripts/oq_validate.sh` → `evidence/oq/gaiaftclconsole_<timestamp>.json`

**GaiaFTCL Console OQ (Xcode `GaiaFTCLConsoleTests`):** policy + signing + telemetry + Sparkle ordering + `InfoPlistTests` — run via `xcodebuild test` (see `oq_validate.sh`). Current suite: **15** XCTest cases (includes `NotificationOrderingTests`, `InfoPlistTests`).

---

### PQ (Performance Qualification) — Swift executable

**TestRobot** (`cells/fusion/macos/TestRobot/`) runs Metal GPU offscreen render tests for both apps:

- **MacFusion PQ:** 64×64 offscreen render, Tokamak red (0.9, 0.1, 0.1), verify non-zero pixels
- **MacHealth PQ:** 64×64 offscreen render, Health blue (0.0, 0.4, 0.9), verify non-zero pixels

Writes:
- Individual receipts: `evidence/pq/macfusion_pq_receipt.json`, `evidence/pq/machealth_pq_receipt.json`
- **Unified receipt:** `evidence/TESTROBOT_RECEIPT.json` (overall status, GPU name, all PQ results)

**Build:**
```zsh
cd cells/fusion/macos/TestRobot
swift build
```

**Run (prefer Aqua / Terminal.app — KERNEL DEADLOCK PROTOCOL):**
```zsh
cells/fusion/scripts/run_testrobot_pq.sh
```

**GaiaFTCL Console PQ:** headed smoke only — does **not** launch GaiaFusion or MacHealth (those stay per-cell).

```zsh
cells/fusion/macos/GaiaFTCLConsole/scripts/pq_smoke.sh
```

Receipt: `evidence/pq/gaiaftclconsole_<timestamp>.json`

### Integration suite (composition receipt)

The **only** artifact that binds Console + both cell apps is the integration receipt (composition, not embedding):

```zsh
cells/fusion/macos/IntegrationTest/scripts/integration_console_plus_cells.sh
```

Writes: `evidence/integration/<timestamp>.json` (template merges per-step hashes). See [`GaiaFTCLConsole/LOCKED.md`](GaiaFTCLConsole/LOCKED.md).

---

## Startup coordination (GaiaFTCL Console)

**Agent limb:** Cursor must not run `bash`/`zsh`/`xcodebuild` against this Mac tree to “prove” builds — see `.cursor/rules/kernel-deadlock-agent-no-mac-shell.mdc`. Operators run qualification in **Terminal.app** (Aqua); drift-close handoffs use explicit **zsh** blocks.

Sparkle must **not** initialize until the operator shell is allowed to run (signing key present, escape hatch, or first-run key generated). The app uses:

| Mechanism | Role |
|-----------|------|
| `Notification.Name.gaiaftclOperatorShellReady` | Posted from `ContentView` when the shell is ready. `AppDelegate` observes it and calls `SparkleUpdaterController.startUpdater()` **once**. |
| `AppDelegate.sparkleFactory` | Test seam (`SparkleUpdaterControlling`); defaults to `SparkleUpdaterController`. |
| `checkForUpdatesFromMenu()` | Starts Sparkle on first use if the notification never fired (lazy path). |

**Who posts:** `ContentView` — when no signing sheet is needed, when `GAIAFTCL_ALLOW_UNSIGNED_RELEASE_LAUNCH=1` allows launch without a key (once, with `first_run` receipt), or after **Generate key now** succeeds. **Quit Console** from the signing sheet does **not** post (writes `evidence/console/first_run_*.json` with `outcome: cancelled` and exits).

**If the notification never fires:** the app stays usable; Sparkle starts on first **Check for Updates…** via `checkForUpdatesFromMenu()`.

**Troubleshooting**

| Symptom | Check |
|--------|--------|
| Sparkle: “Unable to Check For Updates” / updater failed to start | `CFBundleVersion` and `CFBundleShortVersionString` must be set — see `macos/GaiaFTCLConsole/project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). |
| Sparkle signature / appcast errors after startup | `SUPublicEDKey` must match the private key used to sign the appcast; run `zsh macos/GaiaFTCLConsole/scripts/lint_sparkle_release.sh`. |
| PQ screenshot shows signing sheet instead of Launcher | Run `pq_smoke.sh` as-is — it sets a throwaway `GAIAFTCL_CONSOLE_SSH_SIGN_KEY` and stamps `pq_signing_mode: testfixture_ephemeral_key`. |

### Release process — version numbers

- **`MARKETING_VERSION`:** Semver visible to operators (`CFBundleShortVersionString`); align with git release tags when tagging Console releases.
- **`CURRENT_PROJECT_VERSION`:** Monotonic integer string (`CFBundleVersion`); bump on every build you ship to testers, or bind to **CI build number** so Sparkle can compare builds reliably.
- **Ownership:** Release engineer bumps both before tagging; CI may inject `CURRENT_PROJECT_VERSION` via `agvtool` / build setting if you adopt automated numbering.

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
cells/fusion/macos/GaiaFusion/evidence/
├── iq/macfusion_iq_receipt.json
├── oq/macfusion_oq_receipt.json
└── pq/macfusion_pq_receipt.json

cells/fusion/macos/MacHealth/evidence/
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
