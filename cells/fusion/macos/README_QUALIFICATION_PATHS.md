## Mac Qualification — Two Separate IQ/OQ/PQ Paths

**Patents:** USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

---

## Architecture

Canonical qualification paths in this checkout:

```
cells/fusion/macos/
├── GaiaFusion/                  ← MacFusion app (Swift)
├── MacHealth/                   ← MacHealth app (Swift)
├── SILOQRunner/                 ← Active Swift qualification runner
├── TestRobot/                   ← Metal GPU validation
├── CleanCloneTest/              ← Clean clone verifier
├── MacFusionQualification/      ← Legacy path marker (compat)
├── MacHealthQualification/      ← Legacy path marker (compat)
└── QualificationRunner/         ← Legacy path marker (compat)
```

---

## Path 1: MacFusion IQ/OQ/PQ

**Location:** `cells/fusion/macos/SILOQRunner/` (active)

**Build:**
```zsh
cd cells/fusion/macos/SILOQRunner
swift build
```

**Run:**
```zsh
.build/debug/SILOQRunner
```

**Generates:**
- `../GaiaFusion/evidence/iq/macfusion_iq_receipt.json`
- `../GaiaFusion/evidence/oq/macfusion_oq_receipt.json`
- `../GaiaFusion/evidence/pq/macfusion_pq_receipt.json`

**Phases:**
1. **IQ:** Check staticlib (`libgaia_metal_renderer.a`), header, `Package.swift`, build, verify executable
2. **OQ:** Run 6 test suites (CellStateTests, SwapLifecycleTests, PlantKindsCatalogTests, etc.)
3. **PQ:** Metal GPU offscreen render (Tokamak red 0.9/0.1/0.1), verify non-zero pixels

---

## Path 2: MacHealth IQ/OQ/PQ

**Location:** `cells/fusion/macos/SILOQRunner/` (active)

**Build:**
```zsh
cd cells/fusion/macos/SILOQRunner
swift build
```

**Run:**
```zsh
.build/debug/SILOQRunner
```

**Generates:**
- `../MacHealth/evidence/iq/machealth_iq_receipt.json`
- `../MacHealth/evidence/oq/machealth_oq_receipt.json`
- `../MacHealth/evidence/pq/machealth_pq_receipt.json`

**Phases:**
1. **IQ:** Check 3 staticlibs (`libgaia_health_renderer.a`, `libbiologit_md_engine.a`, `libbiologit_usd_parser.a`), header, `Package.swift`, build, verify executable
2. **OQ:** Run 5 tests (testRendererCreateDestroy, testEpistemicRoundTrip, testFrameCountIncrements, testNullHandleSafety, testOutOfRangeEpistemicClamped)
3. **PQ:** Metal GPU offscreen render (Health blue 0.0/0.4/0.9), verify non-zero pixels

---

## TestRobot (Live Test)

**Location:** `cells/fusion/macos/TestRobot/`

**Build:**
```zsh
cd cells/fusion/macos/TestRobot
swift build
```

**Run:**
```zsh
.build/debug/TestRobot
```

**What it does:**
- Runs Metal PQ for **both** MacFusion and MacHealth
- Generates unified `evidence/TESTROBOT_RECEIPT.json`
- **Live test:** TestRobot itself is tested during qualification

---

## SILOQRunner (Orchestrator)

**Location:** `cells/fusion/macos/SILOQRunner/`

**Build:**
```zsh
cd cells/fusion/macos/SILOQRunner
swift build
```

**Run:**
```zsh
.build/debug/SILOQRunner
```

**Orchestration order:**
1. **MacFusion IQ/OQ/PQ** (calls `MacFusionQualification`)
2. **MacHealth IQ/OQ/PQ** (calls `MacHealthQualification`)
3. **TestRobot** (live test)

---

## Test Script (Clean Clone)

**Location:** `cells/fusion/test_qualification_clean_clone.sh`

**What it does:**
1. Creates clean test directory (`~/FoT8D_qualification_test_<timestamp>`)
2. Clones repo from `~/Documents/FoT8D`
3. Checks out `feat/mac-qualification-swift-only` branch
4. Builds MacFusion app
5. Builds MacHealth app
6. Builds all 4 qualification executables
7. Runs `QualificationRunner` (IQ/OQ/PQ + TestRobot)
8. Verifies all 7 receipts present and valid JSON

**Run:**
```zsh
cd /Users/richardgillespie/Documents/GaiaFTCL-MacCells/gaiaFTCL
zsh cells/fusion/test_qualification_clean_clone.sh
```

**Output:**
```
STATE: CALORIE — Clean Clone Test PASS
  ✅ MacFusion: IQ/OQ/PQ verified
  ✅ MacHealth: IQ/OQ/PQ verified
  ✅ TestRobot: Live test verified
  ✅ All receipts: Present and valid (7/7)

Test directory: ~/FoT8D_qualification_test_<timestamp>
```

---

## Receipts Generated (7 total)

**MacFusion (3):**
- `cells/fusion/macos/GaiaFusion/evidence/iq/macfusion_iq_receipt.json`
- `cells/fusion/macos/GaiaFusion/evidence/oq/macfusion_oq_receipt.json`
- `cells/fusion/macos/GaiaFusion/evidence/pq/macfusion_pq_receipt.json`

**MacHealth (3):**
- `cells/fusion/macos/MacHealth/evidence/iq/machealth_iq_receipt.json`
- `cells/fusion/macos/MacHealth/evidence/oq/machealth_oq_receipt.json`
- `cells/fusion/macos/MacHealth/evidence/pq/machealth_pq_receipt.json`

**TestRobot (1):**
- `evidence/TESTROBOT_RECEIPT.json` (unified, both apps)

---

## Why Two Separate Paths?

1. **Independence:** MacFusion and MacHealth have different dependencies, test suites, and FFI contracts
2. **Parallel execution:** Can qualify one app without affecting the other
3. **Clear failure domain:** If MacFusion fails IQ, MacHealth qualification continues
4. **Separate receipts:** Each app has its own audit trail

---

## Live Testing

**TestRobot** is itself **live tested** during qualification:
- It runs after MacFusion and MacHealth complete their IQ/OQ/PQ
- If TestRobot fails, the entire qualification fails
- TestRobot's Metal GPU tests verify both apps' PQ compliance
- Success proves TestRobot is functional (self-validating)

---

**End of document.**

Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie
