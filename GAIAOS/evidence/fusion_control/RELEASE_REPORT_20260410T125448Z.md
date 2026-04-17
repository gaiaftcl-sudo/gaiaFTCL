# GaiaFTCL Closure Battery Report

- ts_utc: 20260410T125448Z
- root: /Users/richardgillespie/Documents/FoT8D/GAIAOS
- head_ip: 77.42.85.60
- ssh_key: /Users/richardgillespie/.ssh/ftclstack-unified

## S4 Fusion Gate
S4_FUSION_GATE: PASS
SELF_HEAL_POLICY: /Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/spec/self-healing-map.json

## Fusion battery
```bash
env GAIA_ROOT=/Users/richardgillespie/Documents/FoT8D/GAIAOS npm run test:fusion:all:local
```

> gaiaos_ui_web@0.1.0 test:fusion:all:local
> bash ../../scripts/test_fusion_all_with_sidecar.sh

 Network fusion_sidecar  Creating
 Network fusion_sidecar  Created
 Container fusion-sidecar-tester  Creating
 Container fusion-sidecar-arangodb  Creating
 Container fusion-sidecar-arangodb  Created
 Container fusion-sidecar-arango-init  Creating
 Container fusion-sidecar-tester  Created
 Container fusion-sidecar-arango-init  Created
 Container fusion-sidecar-gateway  Creating
 Container fusion-sidecar-gateway  Created
 Container fusion-sidecar-arangodb  Starting
 Container fusion-sidecar-tester  Starting
 Container fusion-sidecar-arangodb  Started
 Container fusion-sidecar-arangodb  Waiting
 Container fusion-sidecar-tester  Started
 Container fusion-sidecar-arangodb  Healthy
 Container fusion-sidecar-arango-init  Starting
 Container fusion-sidecar-arango-init  Started
 Container fusion-sidecar-arangodb  Waiting
 Container fusion-sidecar-arango-init  Waiting
 Container fusion-sidecar-arango-init  Exited
 Container fusion-sidecar-arangodb  Healthy
 Container fusion-sidecar-gateway  Starting
 Container fusion-sidecar-gateway  Started

> gaiaos_ui_web@0.1.0 test:fusion:all
> bash ../../scripts/preflight_mcp_gateway.sh && bash ../../scripts/test_fusion_mesh_mooring_stack.sh && npm run test:unit:fusion && npm run test:e2e:fusion

OK gateway http://127.0.0.1:8803/health
PASS bash_n fusion_turbo_ide.sh
PASS bash_n fusion_cell_long_run_runner.sh
PASS bash_n best_control_test_ever.sh
PASS bash_n fusion_mesh_mooring_heartbeat.sh
PASS bash_n mcp_bridge_torax
PASS bash_n mcp_bridge_marte2
PASS projection_payment
PASS payment_proj_fn
PASS mooring_status
PASS torax_refused
PASS marte2_refused
PASS jsonl_merge
PASS degraded_shape
PASS heartbeat_refused_no_setup
PASS best_control
--- PASSED=15 FAILED=0 ---

> gaiaos_ui_web@0.1.0 test:unit:fusion
> vitest run


 RUN  v3.2.4 /Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web

 ✓ tests/unit/fusionChallengeLedger.cjs.test.ts (1 test) 4ms
 ✓ tests/unit/fusionS4PcsTelemetry.test.ts (4 tests) 3ms
 ✓ tests/unit/fusionS4Gates.test.ts (13 tests) 5ms
 ✓ tests/unit/fusionFleetSnapshotParse.test.ts (5 tests) 2ms
 ✓ tests/unit/dmgSignedUrl.test.ts (7 tests) 4ms
 ✓ tests/unit/fusionS4GlobalChallenge.test.ts (1 test) 2ms

 Test Files  6 passed (6)
      Tests  31 passed (31)
   Start at  08:55:00
   Duration  346ms (transform 120ms, setup 0ms, collect 224ms, tests 19ms, environment 1ms, prepare 372ms)


> gaiaos_ui_web@0.1.0 test:e2e:fusion
> playwright test --config=playwright.fusion.config.ts


Running 23 tests using 1 worker

  -   1 [chromium] › tests/fusion/fusion_dashboard_visual_witness.spec.ts:16:7 › Fusion Dashboard visual witness › fusion-s4 rendered + high-res PNG
  -   2 [chromium] › tests/fusion/fusion_mac_wasm_gate.spec.ts:8:7 › fusion_mac_wasm_gate › substrate + fusion health + self_heal contract from embedded LocalServer
  ✓   3 [chromium] › tests/fusion/fusion_mac_wasm_gate.spec.ts:60:7 › fusion_mac_wasm_gate › fusion-s4 renders active operator surface (not stuck splash) (349ms)
  -   4 [chromium] › tests/fusion/fusion_matrix_e2e.spec.ts:4:7 › Fusion matrix API (slow) › runMatrix=1 with minimal cycles when FUSION_MATRIX_E2E=1
  ✓   5 [chromium] › tests/fusion/fusion_s4_console.spec.ts:265:7 › Fusion S4 console › fusion console swap panel mounts after mooring transition (501ms)
  ✓   6 [chromium] › tests/fusion/fusion_s4_console.spec.ts:280:7 › Fusion S4 console › GET /api/fusion/s4-projection contract (34ms)
  ✓   7 [chromium] › tests/fusion/fusion_s4_console.spec.ts:392:7 › Fusion S4 console › GET /api/fusion/mesh-operator-spine contract (12ms)
  ✓   8 [chromium] › tests/fusion/fusion_s4_console.spec.ts:400:7 › Fusion S4 console › GET /api/fusion/soak-summary contract (18ms)
  ✓   9 [chromium] › tests/fusion/fusion_s4_console.spec.ts:422:7 › Fusion S4 console › GET /api/fusion/challenge-ledger read contract (8ms)
  ✓  10 [chromium] › tests/fusion/fusion_s4_console.spec.ts:430:7 › Fusion S4 console › POST /api/fusion/challenge-ledger registers team (secret) (9ms)
  ✓  11 [chromium] › tests/fusion/fusion_s4_console.spec.ts:452:7 › Fusion S4 console › GET /api/fusion/global-challenge-digest (11ms)
  ✓  12 [chromium] › tests/fusion/fusion_s4_console.spec.ts:462:7 › Fusion S4 console › GET /api/fusion/soak-summary markdown export (39ms)
  ✓  13 [chromium] › tests/fusion/fusion_s4_console.spec.ts:471:7 › Fusion S4 console › /fusion-s4 UI panels (474ms)
  ✓  14 [chromium] › tests/fusion/fusion_s4_console.spec.ts:491:7 › Fusion S4 console › WASM projection event propagates from bridge payload to control shell and viewport (632ms)
  ✓  15 [chromium] › tests/fusion/fusion_s4_console.spec.ts:695:7 › Fusion S4 console › WASM UI self-heals missing anchors and UI state without external input (1.9s)
  ✓  16 [chromium] › tests/fusion/fusion_s4_console.spec.ts:818:7 › Fusion S4 console › Soak table lists four JSONL tracks (373ms)
  ✓  17 [chromium] › tests/fusion/fusion_s4_console.spec.ts:825:7 › Fusion S4 console › OpenUSD gameplay witness: run matrix + USD overlay hash (446ms)
  ✓  18 [chromium] › tests/fusion/fusion_s4_console.spec.ts:866:7 › Fusion S4 console › MSV Stage 4 linguistic eversion + low-latency MUTATE_VARIANT witness (679ms)
  ✓  19 [chromium] › tests/fusion/fusion_s4_doc.spec.ts:11:7 › Fusion S4 documentation capture › full-page screenshot @fusion-doc (362ms)
  ✓  20 [chromium] › tests/fusion/gate1_page.spec.ts:7:7 › GATE1 page › gate1 page loads and shows custody copy (236ms)
  ✓  21 [chromium] › tests/fusion/gate1_page.spec.ts:13:7 › GATE1 page › gate1-register-options GET returns JSON (8ms)
  ✓  22 [chromium] › tests/fusion/gate1_page.spec.ts:21:7 › GATE1 page › gate1-register-options POST is 403 until GATE1_LIFT=1 (7ms)
  -  23 [chromium] › tests/fusion/mesh_game_runner_capture.spec.ts:90:7 › Mesh game runner capture › capture all mesh domain GUI gameplay without Discord

  4 skipped
  19 passed (12.3s)
RESULT: PASS

## B7-gaiafusion-mac-release-smoke
```bash
env GAIAFUSION_SKIP_MAC_CELL_MCP=1 bash /Users/richardgillespie/Documents/FoT8D/GAIAOS/scripts/run_gaiafusion_release_smoke.sh
```
━━ GaiaFusion release smoke (GAIAOS=/Users/richardgillespie/Documents/FoT8D/GAIAOS) ━━
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.82s)
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--58304C5D6DBC2206.txt
[2/4] Emitting module GaiaFusionTests
[2/4] Write Objects.LinkFileList
[3/4] Linking GaiaFusionPackageTests
Build complete! (1.11s)
Test Suite 'All tests' started at 2026-04-10 08:55:28.748.
Test Suite 'GaiaFusionPackageTests.xctest' started at 2026-04-10 08:55:28.749.
Test Suite 'CellStateTests' started at 2026-04-10 08:55:28.749.
Test Case '-[GaiaFusionTests.CellStateTests testFallbackCellIsHealthyTextFallback]' started.
Test Case '-[GaiaFusionTests.CellStateTests testFallbackCellIsHealthyTextFallback]' passed (0.001 seconds).
Test Case '-[GaiaFusionTests.CellStateTests testHealthPercentConvertsToPercentScale]' started.
Test Case '-[GaiaFusionTests.CellStateTests testHealthPercentConvertsToPercentScale]' passed (0.000 seconds).
Test Suite 'CellStateTests' passed at 2026-04-10 08:55:28.750.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ConfigValidationTests' started at 2026-04-10 08:55:28.750.
Test Case '-[GaiaFusionTests.ConfigValidationTests testFileTreeReturnsConfiguredRoot]' started.
Test Case '-[GaiaFusionTests.ConfigValidationTests testFileTreeReturnsConfiguredRoot]' passed (0.004 seconds).
Test Case '-[GaiaFusionTests.ConfigValidationTests testFusionCellRuntimeConfigURLMatchesRunnerPath]' started.
Test Case '-[GaiaFusionTests.ConfigValidationTests testFusionCellRuntimeConfigURLMatchesRunnerPath]' passed (0.002 seconds).
Test Case '-[GaiaFusionTests.ConfigValidationTests testIsValidJSONForWellFormedAndMalformedText]' started.
Test Case '-[GaiaFusionTests.ConfigValidationTests testIsValidJSONForWellFormedAndMalformedText]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.ConfigValidationTests testWriteReadRoundTripForJSONFile]' started.
Test Case '-[GaiaFusionTests.ConfigValidationTests testWriteReadRoundTripForJSONFile]' passed (0.001 seconds).
Test Suite 'ConfigValidationTests' passed at 2026-04-10 08:55:28.758.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.007 (0.007) seconds
Test Suite 'LocalServerAPITests' started at 2026-04-10 08:55:28.758.
Test Case '-[GaiaFusionTests.LocalServerAPITests testBridgeStatusEndpointReportsBooleanShape]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testBridgeStatusEndpointReportsBooleanShape]' passed (0.080 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testCellsEndpointReturnsAllConfiguredNodes]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testCellsEndpointReturnsAllConfiguredNodes]' passed (0.011 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testFleetDigestEndpointReturnsTopologyShape]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testFleetDigestEndpointReturnsTopologyShape]' passed (0.010 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testHealthEndpointReturnsOperationalPayload]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testHealthEndpointReturnsOperationalPayload]' passed (0.013 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testPlantKindsEndpointReturnsCanonicalKinds]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testPlantKindsEndpointReturnsCanonicalKinds]' passed (0.010 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testS4ProjectionEndpointReturnsProjectionShape]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testS4ProjectionEndpointReturnsProjectionShape]' passed (0.011 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSelfProbeEndpointReturnsSchemaAndBridgeGate]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSelfProbeEndpointReturnsSchemaAndBridgeGate]' passed (0.024 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSovereignMeshEndpointReturnsExpectedShape]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSovereignMeshEndpointReturnsExpectedShape]' passed (0.016 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapEndpointRejectsWithoutQuorum]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapEndpointRejectsWithoutQuorum]' passed (0.014 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapRejectsUnknownPlantKind]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapRejectsUnknownPlantKind]' passed (0.010 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapRejectsUnsupportedPlantKind]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapRejectsUnsupportedPlantKind]' passed (0.015 seconds).
Test Suite 'LocalServerAPITests' passed at 2026-04-10 08:55:28.973.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.215 (0.216) seconds
Test Suite 'MeshProbeTests' started at 2026-04-10 08:55:28.973.
Test Case '-[GaiaFusionTests.MeshProbeTests testProjectionPayloadDefaults]' started.
Test Case '-[GaiaFusionTests.MeshProbeTests testProjectionPayloadDefaults]' passed (0.001 seconds).
Test Case '-[GaiaFusionTests.MeshProbeTests testProjectionReportsRecentSwaps]' started.
Test Case '-[GaiaFusionTests.MeshProbeTests testProjectionReportsRecentSwaps]' passed (0.000 seconds).
Test Suite 'MeshProbeTests' passed at 2026-04-10 08:55:28.974.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'PlantKindsCatalogTests' started at 2026-04-10 08:55:28.974.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testCanonicalKindsPassThrough]' started.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testCanonicalKindsPassThrough]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testLegacyAliasesResolveToCanonicalKinds]' started.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testLegacyAliasesResolveToCanonicalKinds]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testSharedCatalogNonEmpty]' started.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testSharedCatalogNonEmpty]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testUnknownKindRefused]' started.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testUnknownKindRefused]' passed (0.000 seconds).
Test Suite 'PlantKindsCatalogTests' passed at 2026-04-10 08:55:28.975.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'SwapLifecycleTests' started at 2026-04-10 08:55:28.975.
Test Case '-[GaiaFusionTests.SwapLifecycleTests testExplicitSwapKindPassthrough]' started.
Test Case '-[GaiaFusionTests.SwapLifecycleTests testExplicitSwapKindPassthrough]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.SwapLifecycleTests testSwapLifecycleAdvances]' started.
Test Case '-[GaiaFusionTests.SwapLifecycleTests testSwapLifecycleAdvances]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.SwapLifecycleTests testSwapLifecycleStartsRequested]' started.
Test Case '-[GaiaFusionTests.SwapLifecycleTests testSwapLifecycleStartsRequested]' passed (0.000 seconds).
Test Suite 'SwapLifecycleTests' passed at 2026-04-10 08:55:28.976.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'GaiaFusionPackageTests.xctest' passed at 2026-04-10 08:55:28.976.
	 Executed 26 tests, with 0 failures (0 unexpected) in 0.224 (0.227) seconds
Test Suite 'All tests' passed at 2026-04-10 08:55:28.976.
	 Executed 26 tests, with 0 failures (0 unexpected) in 0.224 (0.228) seconds
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
[PlantKindsCatalog] REFUSED: unsupported plant kind "unknown"
GaiaFusion: detected Next dev server on 127.0.0.1:3002 (fusion-s4)
GaiaFusion server on 127.0.0.1:8945 (static)
[PlantKindsCatalog] REFUSED: unsupported plant kind "hybrid"
[PlantKindsCatalog] legacy alias resolved: "virtual" -> "tokamak"
[PlantKindsCatalog] legacy alias resolved: "real" -> "tokamak"
[PlantKindsCatalog] REFUSED: unsupported plant kind "not_a_plant_kind"
◇ Test run started.
↳ Testing Library Version: 1743
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
━━ GaiaFusion working-app gate attempt 1/3 ━━
/Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/fusion_mac_app_gate_receipt.json
CURE: GaiaFusion composite + build + runtime + Playwright substrate API gate passed
━━ In-app self-probe (HTTP CLI → /api/fusion/self-probe) ━━
CURE: GaiaFusion working-app verify — /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/gaiafusion_working_app_verify_receipt.json
CURE: GaiaFusion release smoke — /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/gaiafusion_release_smoke_receipt.json
RESULT: PASS

## Zero-Ghost Uniformity (head vs 9 cells)
HEAD_SHA: 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-hcloud-hel1-01 77.42.85.60 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-hcloud-hel1-02 135.181.88.134 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-hcloud-hel1-03 77.42.32.156 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-hcloud-hel1-04 77.42.88.110 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-hcloud-hel1-05 37.27.7.9 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-netcup-nbg1-01 37.120.187.247 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-netcup-nbg1-02 152.53.91.220 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-netcup-nbg1-03 152.53.88.141 20260406T162209Z-14dc08e40ed4
UNIFORM: gaiaftcl-netcup-nbg1-04 37.120.187.174 20260406T162209Z-14dc08e40ed4
UNIFORMITY_VERDICT: UNIFORM

STATE: CALORIE
REPORT_JSON: /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/RELEASE_REPORT_20260410T125448Z.json
REPORT_MD: /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/RELEASE_REPORT_20260410T125448Z.md
