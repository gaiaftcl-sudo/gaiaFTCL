# GaiaFTCL Closure Battery Report

- ts_utc: 20260410T152114Z
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
 Container fusion-sidecar-tester  Created
 Container fusion-sidecar-arangodb  Created
 Container fusion-sidecar-arango-init  Creating
 Container fusion-sidecar-arango-init  Created
 Container fusion-sidecar-gateway  Creating
 Container fusion-sidecar-gateway  Created
 Container fusion-sidecar-tester  Starting
 Container fusion-sidecar-arangodb  Starting
 Container fusion-sidecar-arangodb  Started
 Container fusion-sidecar-arangodb  Waiting
 Container fusion-sidecar-tester  Started
 Container fusion-sidecar-arangodb  Healthy
 Container fusion-sidecar-arango-init  Starting
 Container fusion-sidecar-arango-init  Started
 Container fusion-sidecar-arango-init  Waiting
 Container fusion-sidecar-arangodb  Waiting
 Container fusion-sidecar-arangodb  Healthy
 Container fusion-sidecar-arango-init  Exited
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

 ✓ tests/unit/fusionChallengeLedger.cjs.test.ts (1 test) 9ms
 ✓ tests/unit/wasmManifoldBridge.test.ts (3 tests) 6ms
 ✓ tests/unit/fusionFleetSnapshotParse.test.ts (5 tests) 6ms
 ✓ tests/unit/fusionS4Gates.test.ts (13 tests) 12ms
 ✓ tests/unit/dmgSignedUrl.test.ts (7 tests) 10ms
 ✓ tests/unit/fusionS4PcsTelemetry.test.ts (4 tests) 6ms
 ✓ tests/unit/fusionS4GlobalChallenge.test.ts (1 test) 6ms

 Test Files  7 passed (7)
      Tests  34 passed (34)
   Start at  11:21:27
   Duration  857ms (transform 561ms, setup 0ms, collect 1.06s, tests 55ms, environment 2ms, prepare 1.61s)


> gaiaos_ui_web@0.1.0 test:e2e:fusion
> playwright test --config=playwright.fusion.config.ts


Running 23 tests using 1 worker

  -   1 [chromium] › tests/fusion/fusion_dashboard_visual_witness.spec.ts:16:7 › Fusion Dashboard visual witness › fusion-s4 rendered + high-res PNG
  -   2 [chromium] › tests/fusion/fusion_mac_wasm_gate.spec.ts:8:7 › fusion_mac_wasm_gate › substrate + fusion health + self_heal contract from embedded LocalServer
  ✓   3 [chromium] › tests/fusion/fusion_mac_wasm_gate.spec.ts:60:7 › fusion_mac_wasm_gate › fusion-s4 renders active operator surface (not stuck splash) (613ms)
  -   4 [chromium] › tests/fusion/fusion_matrix_e2e.spec.ts:4:7 › Fusion matrix API (slow) › runMatrix=1 with minimal cycles when FUSION_MATRIX_E2E=1
  ✓   5 [chromium] › tests/fusion/fusion_s4_console.spec.ts:265:7 › Fusion S4 console › fusion console swap panel mounts after mooring transition (695ms)
  ✓   6 [chromium] › tests/fusion/fusion_s4_console.spec.ts:280:7 › Fusion S4 console › GET /api/fusion/s4-projection contract (560ms)
  ✓   7 [chromium] › tests/fusion/fusion_s4_console.spec.ts:392:7 › Fusion S4 console › GET /api/fusion/mesh-operator-spine contract (94ms)
  ✓   8 [chromium] › tests/fusion/fusion_s4_console.spec.ts:400:7 › Fusion S4 console › GET /api/fusion/soak-summary contract (131ms)
  ✓   9 [chromium] › tests/fusion/fusion_s4_console.spec.ts:422:7 › Fusion S4 console › GET /api/fusion/challenge-ledger read contract (70ms)
  ✓  10 [chromium] › tests/fusion/fusion_s4_console.spec.ts:430:7 › Fusion S4 console › POST /api/fusion/challenge-ledger registers team (secret) (49ms)
  ✓  11 [chromium] › tests/fusion/fusion_s4_console.spec.ts:452:7 › Fusion S4 console › GET /api/fusion/global-challenge-digest (126ms)
  ✓  12 [chromium] › tests/fusion/fusion_s4_console.spec.ts:462:7 › Fusion S4 console › GET /api/fusion/soak-summary markdown export (257ms)
  ✓  13 [chromium] › tests/fusion/fusion_s4_console.spec.ts:471:7 › Fusion S4 console › /fusion-s4 UI panels (687ms)
  ✓  14 [chromium] › tests/fusion/fusion_s4_console.spec.ts:491:7 › Fusion S4 console › WASM projection event propagates from bridge payload to control shell and viewport (2.0s)
  ✓  15 [chromium] › tests/fusion/fusion_s4_console.spec.ts:695:7 › Fusion S4 console › WASM UI self-heals missing anchors and UI state without external input (2.2s)
  ✓  16 [chromium] › tests/fusion/fusion_s4_console.spec.ts:818:7 › Fusion S4 console › Soak table lists four JSONL tracks (2.2s)
  ✓  17 [chromium] › tests/fusion/fusion_s4_console.spec.ts:825:7 › Fusion S4 console › OpenUSD gameplay witness: run matrix + USD overlay hash (1.8s)
  ✘  18 [chromium] › tests/fusion/fusion_s4_console.spec.ts:866:7 › Fusion S4 console › MSV Stage 4 linguistic eversion + low-latency MUTATE_VARIANT witness (1.3s)
  ✓  19 [chromium] › tests/fusion/fusion_s4_doc.spec.ts:11:7 › Fusion S4 documentation capture › full-page screenshot @fusion-doc (1.6s)
  ✓  20 [chromium] › tests/fusion/gate1_page.spec.ts:7:7 › GATE1 page › gate1 page loads and shows custody copy (834ms)
  ✓  21 [chromium] › tests/fusion/gate1_page.spec.ts:13:7 › GATE1 page › gate1-register-options GET returns JSON (54ms)
  ✓  22 [chromium] › tests/fusion/gate1_page.spec.ts:21:7 › GATE1 page › gate1-register-options POST is 403 until GATE1_LIFT=1 (40ms)
  -  23 [chromium] › tests/fusion/mesh_game_runner_capture.spec.ts:90:7 › Mesh game runner capture › capture all mesh domain GUI gameplay without Discord


  1) [chromium] › tests/fusion/fusion_s4_console.spec.ts:866:7 › Fusion S4 console › MSV Stage 4 linguistic eversion + low-latency MUTATE_VARIANT witness 

    Error: [2mexpect([22m[31mreceived[39m[2m).[22mtoBeTruthy[2m()[22m

    Received: [31mfalse[39m

      1010 |       const afterMarkup = await captureShell();
      1011 |       const stableShell = beforeMarkup === afterMarkup;
    > 1012 |       expect(stableShell).toBeTruthy();
           |                           ^
      1013 |
      1014 |       if (process.env.FUSION_VISUAL_WITNESS === "1") {
      1015 |         await page.screenshot({
        at /Users/richardgillespie/Documents/FoT8D/GAIAOS/services/gaiaos_ui_web/tests/fusion/fusion_s4_console.spec.ts:1012:27

    attachment #1: screenshot (image/png) ──────────────────────────────────────────────────────────
    test-results/fusion_s4_console-Fusion-S-b8297-ency-MUTATE-VARIANT-witness-chromium/test-failed-1.png
    ────────────────────────────────────────────────────────────────────────────────────────────────

    Error Context: test-results/fusion_s4_console-Fusion-S-b8297-ency-MUTATE-VARIANT-witness-chromium/error-context.md

  1 failed
    [chromium] › tests/fusion/fusion_s4_console.spec.ts:866:7 › Fusion S4 console › MSV Stage 4 linguistic eversion + low-latency MUTATE_VARIANT witness 
  4 skipped
  18 passed (24.7s)
RESULT: FAIL
SELF_HEAL: retrying Fusion battery (attempt 1/1) from domain map

## Fusion battery (self-heal retry 1)
```bash
env GAIA_ROOT=/Users/richardgillespie/Documents/FoT8D/GAIAOS npm run test:fusion:all:local
```

> gaiaos_ui_web@0.1.0 test:fusion:all:local
> bash ../../scripts/test_fusion_all_with_sidecar.sh

 Network fusion_sidecar  Creating
 Network fusion_sidecar  Created
 Container fusion-sidecar-arangodb  Creating
 Container fusion-sidecar-tester  Creating
 Container fusion-sidecar-arangodb  Created
 Container fusion-sidecar-arango-init  Creating
 Container fusion-sidecar-tester  Created
 Container fusion-sidecar-arango-init  Created
 Container fusion-sidecar-gateway  Creating
 Container fusion-sidecar-gateway  Created
 Container fusion-sidecar-tester  Starting
 Container fusion-sidecar-arangodb  Starting
 Container fusion-sidecar-arangodb  Started
 Container fusion-sidecar-arangodb  Waiting
 Container fusion-sidecar-tester  Started
 Container fusion-sidecar-arangodb  Healthy
 Container fusion-sidecar-arango-init  Starting
 Container fusion-sidecar-arango-init  Started
 Container fusion-sidecar-arangodb  Waiting
 Container fusion-sidecar-arango-init  Waiting
 Container fusion-sidecar-arangodb  Healthy
 Container fusion-sidecar-arango-init  Exited
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

 ✓ tests/unit/fusionFleetSnapshotParse.test.ts (5 tests) 6ms
 ✓ tests/unit/wasmManifoldBridge.test.ts (3 tests) 7ms
 ✓ tests/unit/fusionS4PcsTelemetry.test.ts (4 tests) 6ms
 ✓ tests/unit/fusionChallengeLedger.cjs.test.ts (1 test) 13ms
 ✓ tests/unit/fusionS4Gates.test.ts (13 tests) 13ms
 ✓ tests/unit/fusionS4GlobalChallenge.test.ts (1 test) 7ms
 ✓ tests/unit/dmgSignedUrl.test.ts (7 tests) 8ms

 Test Files  7 passed (7)
      Tests  34 passed (34)
   Start at  11:22:20
   Duration  942ms (transform 322ms, setup 0ms, collect 501ms, tests 60ms, environment 1ms, prepare 1.65s)


> gaiaos_ui_web@0.1.0 test:e2e:fusion
> playwright test --config=playwright.fusion.config.ts


Running 23 tests using 1 worker

  -   1 [chromium] › tests/fusion/fusion_dashboard_visual_witness.spec.ts:16:7 › Fusion Dashboard visual witness › fusion-s4 rendered + high-res PNG
  -   2 [chromium] › tests/fusion/fusion_mac_wasm_gate.spec.ts:8:7 › fusion_mac_wasm_gate › substrate + fusion health + self_heal contract from embedded LocalServer
  ✓   3 [chromium] › tests/fusion/fusion_mac_wasm_gate.spec.ts:60:7 › fusion_mac_wasm_gate › fusion-s4 renders active operator surface (not stuck splash) (1.1s)
  -   4 [chromium] › tests/fusion/fusion_matrix_e2e.spec.ts:4:7 › Fusion matrix API (slow) › runMatrix=1 with minimal cycles when FUSION_MATRIX_E2E=1
  ✓   5 [chromium] › tests/fusion/fusion_s4_console.spec.ts:265:7 › Fusion S4 console › fusion console swap panel mounts after mooring transition (1.0s)
  ✓   6 [chromium] › tests/fusion/fusion_s4_console.spec.ts:280:7 › Fusion S4 console › GET /api/fusion/s4-projection contract (535ms)
  ✓   7 [chromium] › tests/fusion/fusion_s4_console.spec.ts:392:7 › Fusion S4 console › GET /api/fusion/mesh-operator-spine contract (80ms)
  ✓   8 [chromium] › tests/fusion/fusion_s4_console.spec.ts:400:7 › Fusion S4 console › GET /api/fusion/soak-summary contract (153ms)
  ✓   9 [chromium] › tests/fusion/fusion_s4_console.spec.ts:422:7 › Fusion S4 console › GET /api/fusion/challenge-ledger read contract (24ms)
  ✓  10 [chromium] › tests/fusion/fusion_s4_console.spec.ts:430:7 › Fusion S4 console › POST /api/fusion/challenge-ledger registers team (secret) (36ms)
  ✓  11 [chromium] › tests/fusion/fusion_s4_console.spec.ts:452:7 › Fusion S4 console › GET /api/fusion/global-challenge-digest (238ms)
  ✓  12 [chromium] › tests/fusion/fusion_s4_console.spec.ts:462:7 › Fusion S4 console › GET /api/fusion/soak-summary markdown export (154ms)
  ✓  13 [chromium] › tests/fusion/fusion_s4_console.spec.ts:471:7 › Fusion S4 console › /fusion-s4 UI panels (1.7s)
  ✓  14 [chromium] › tests/fusion/fusion_s4_console.spec.ts:491:7 › Fusion S4 console › WASM projection event propagates from bridge payload to control shell and viewport (3.1s)
  ✓  15 [chromium] › tests/fusion/fusion_s4_console.spec.ts:695:7 › Fusion S4 console › WASM UI self-heals missing anchors and UI state without external input (2.3s)
  ✓  16 [chromium] › tests/fusion/fusion_s4_console.spec.ts:818:7 › Fusion S4 console › Soak table lists four JSONL tracks (1.3s)
  ✓  17 [chromium] › tests/fusion/fusion_s4_console.spec.ts:825:7 › Fusion S4 console › OpenUSD gameplay witness: run matrix + USD overlay hash (2.6s)
  ✓  18 [chromium] › tests/fusion/fusion_s4_console.spec.ts:866:7 › Fusion S4 console › MSV Stage 4 linguistic eversion + low-latency MUTATE_VARIANT witness (1.6s)
  ✓  19 [chromium] › tests/fusion/fusion_s4_doc.spec.ts:11:7 › Fusion S4 documentation capture › full-page screenshot @fusion-doc (804ms)
  ✓  20 [chromium] › tests/fusion/gate1_page.spec.ts:7:7 › GATE1 page › gate1 page loads and shows custody copy (1.0s)
  ✓  21 [chromium] › tests/fusion/gate1_page.spec.ts:13:7 › GATE1 page › gate1-register-options GET returns JSON (66ms)
  ✓  22 [chromium] › tests/fusion/gate1_page.spec.ts:21:7 › GATE1 page › gate1-register-options POST is 403 until GATE1_LIFT=1 (77ms)
  -  23 [chromium] › tests/fusion/mesh_game_runner_capture.spec.ts:90:7 › Mesh game runner capture › capture all mesh domain GUI gameplay without Discord

  4 skipped
  19 passed (27.0s)
RESULT: PASS

## B7-gaiafusion-mac-release-smoke
```bash
env GAIAFUSION_SKIP_MAC_CELL_MCP=1 bash /Users/richardgillespie/Documents/FoT8D/GAIAOS/scripts/run_gaiafusion_release_smoke.sh
```
━━ GaiaFusion release smoke (GAIAOS=/Users/richardgillespie/Documents/FoT8D/GAIAOS) ━━
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--58304C5D6DBC2206.txt
[2/24] Compiling Swifter String+Misc.swift
[3/25] Compiling Swifter String+File.swift
[4/25] Compiling Swifter String+BASE64.swift
[5/25] Compiling Swifter String+SHA1.swift
[6/25] Compiling Swifter Socket+Server.swift
[7/25] Compiling Swifter Socket+File.swift
[8/25] Compiling Swifter Socket.swift
[9/25] Compiling Swifter HttpServerIO.swift
[10/25] Compiling Swifter MimeTypes.swift
[11/25] Compiling Swifter Process.swift
[12/25] Compiling Swifter HttpRouter.swift
[13/25] Compiling Swifter HttpServer.swift
[14/25] Compiling Swifter HttpRequest.swift
[15/25] Compiling Swifter HttpResponse.swift
[16/25] Compiling Swifter Files.swift
[17/25] Compiling Swifter HttpParser.swift
[18/25] Compiling Swifter DemoServer.swift
[19/25] Compiling Swifter Errno.swift
[20/25] Emitting module Swifter
[21/25] Compiling Swifter Scopes.swift
[22/25] Compiling Swifter WebSockets.swift
[23/59] Compiling GaiaFusion UIStateManifold.swift
[24/59] Compiling GaiaFusion WasmAssemblyQueue.swift
[25/61] Compiling GaiaFusion PlantKindPicker.swift
[26/61] Compiling GaiaFusion resource_bundle_accessor.swift
[27/61] Compiling GaiaFusion CellDetailTab.swift
[28/61] Compiling GaiaFusion ConfigEditorTab.swift
[29/61] Compiling GaiaFusion MeshCellListView.swift
[30/61] Compiling GaiaFusion ResultsBrowser.swift
[31/61] Compiling GaiaFusion CellState.swift
[32/61] Compiling GaiaFusion OpenUSDLanguageGames.swift
[33/61] Compiling GaiaFusion InspectorPanel.swift
[34/61] Compiling GaiaFusion ReceiptViewerTab.swift
[35/61] Compiling GaiaFusion NATSMCPBridge.swift
[36/61] Compiling GaiaFusion NATSService.swift
[37/61] Emitting module GaiaFusion
[38/61] Compiling GaiaFusion FusionBridge.swift
[39/61] Compiling GaiaFusion FusionEmbeddedAssetGate.swift
[40/61] Compiling GaiaFusion FusionSidecarCellBundle.swift
[41/61] Compiling GaiaFusion SwapState.swift
[42/61] Compiling GaiaFusion ConfigFileManager.swift
[43/61] Compiling GaiaFusion SSHService.swift
[44/61] Compiling GaiaFusion UIDecimator.swift
[45/61] Compiling GaiaFusion PlantKindsCatalog.swift
[46/61] Compiling GaiaFusion ProjectionState.swift
[47/61] Compiling GaiaFusion StatusBarView.swift
[48/61] Compiling GaiaFusion FusionToolbar.swift
[49/61] Compiling GaiaFusion OnboardingFlow.swift
[50/61] Compiling GaiaFusion AppMenu.swift
[51/61] Compiling GaiaFusion ConfigPanel.swift
[52/61] Compiling GaiaFusion LocalServer.swift
[53/61] Compiling GaiaFusion MeshStateManager.swift
[54/61] Compiling GaiaFusion FusionUiTorsion.swift
[55/61] Compiling GaiaFusion FusionWebView.swift
[56/61] Compiling GaiaFusion GaiaFusionApp.swift
[57/61] Compiling GaiaFusion ConfigFileBrowser.swift
[58/61] Compiling GaiaFusion FusionSidebarView.swift
[58/61] Write Objects.LinkFileList
[59/61] Linking GaiaFusion
[60/61] Applying GaiaFusion
Build complete! (8.00s)
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--58304C5D6DBC2206.txt
[2/4] Emitting module GaiaFusionTests
[2/4] Write Objects.LinkFileList
[3/4] Linking GaiaFusionPackageTests
Build complete! (1.33s)
Test Suite 'All tests' started at 2026-04-10 11:23:12.181.
Test Suite 'GaiaFusionPackageTests.xctest' started at 2026-04-10 11:23:12.182.
Test Suite 'CellStateTests' started at 2026-04-10 11:23:12.182.
Test Case '-[GaiaFusionTests.CellStateTests testFallbackCellIsHealthyTextFallback]' started.
Test Case '-[GaiaFusionTests.CellStateTests testFallbackCellIsHealthyTextFallback]' passed (0.001 seconds).
Test Case '-[GaiaFusionTests.CellStateTests testHealthPercentConvertsToPercentScale]' started.
Test Case '-[GaiaFusionTests.CellStateTests testHealthPercentConvertsToPercentScale]' passed (0.000 seconds).
Test Suite 'CellStateTests' passed at 2026-04-10 11:23:12.183.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ConfigValidationTests' started at 2026-04-10 11:23:12.183.
Test Case '-[GaiaFusionTests.ConfigValidationTests testFileTreeReturnsConfiguredRoot]' started.
Test Case '-[GaiaFusionTests.ConfigValidationTests testFileTreeReturnsConfiguredRoot]' passed (0.003 seconds).
Test Case '-[GaiaFusionTests.ConfigValidationTests testFusionCellRuntimeConfigURLMatchesRunnerPath]' started.
Test Case '-[GaiaFusionTests.ConfigValidationTests testFusionCellRuntimeConfigURLMatchesRunnerPath]' passed (0.001 seconds).
Test Case '-[GaiaFusionTests.ConfigValidationTests testIsValidJSONForWellFormedAndMalformedText]' started.
Test Case '-[GaiaFusionTests.ConfigValidationTests testIsValidJSONForWellFormedAndMalformedText]' passed (0.001 seconds).
Test Case '-[GaiaFusionTests.ConfigValidationTests testWriteReadRoundTripForJSONFile]' started.
Test Case '-[GaiaFusionTests.ConfigValidationTests testWriteReadRoundTripForJSONFile]' passed (0.001 seconds).
Test Suite 'ConfigValidationTests' passed at 2026-04-10 11:23:12.190.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.006 (0.007) seconds
Test Suite 'LocalServerAPITests' started at 2026-04-10 11:23:12.190.
Test Case '-[GaiaFusionTests.LocalServerAPITests testBridgeStatusEndpointReportsBooleanShape]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testBridgeStatusEndpointReportsBooleanShape]' passed (0.054 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testCellsEndpointReturnsAllConfiguredNodes]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testCellsEndpointReturnsAllConfiguredNodes]' passed (0.015 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testFleetDigestEndpointReturnsTopologyShape]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testFleetDigestEndpointReturnsTopologyShape]' passed (0.014 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testHealthEndpointReturnsOperationalPayload]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testHealthEndpointReturnsOperationalPayload]' passed (0.013 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testPlantKindsEndpointReturnsCanonicalKinds]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testPlantKindsEndpointReturnsCanonicalKinds]' passed (0.013 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testS4ProjectionEndpointReturnsProjectionShape]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testS4ProjectionEndpointReturnsProjectionShape]' passed (0.014 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSelfProbeEndpointReturnsSchemaAndBridgeGate]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSelfProbeEndpointReturnsSchemaAndBridgeGate]' passed (0.013 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSovereignMeshEndpointReturnsExpectedShape]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSovereignMeshEndpointReturnsExpectedShape]' passed (0.014 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapEndpointRejectsWithoutQuorum]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapEndpointRejectsWithoutQuorum]' passed (0.015 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapRejectsUnknownPlantKind]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapRejectsUnknownPlantKind]' passed (0.013 seconds).
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapRejectsUnsupportedPlantKind]' started.
Test Case '-[GaiaFusionTests.LocalServerAPITests testSwapRejectsUnsupportedPlantKind]' passed (0.012 seconds).
Test Suite 'LocalServerAPITests' passed at 2026-04-10 11:23:12.382.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.190 (0.192) seconds
Test Suite 'MeshProbeTests' started at 2026-04-10 11:23:12.382.
Test Case '-[GaiaFusionTests.MeshProbeTests testProjectionPayloadDefaults]' started.
Test Case '-[GaiaFusionTests.MeshProbeTests testProjectionPayloadDefaults]' passed (0.001 seconds).
Test Case '-[GaiaFusionTests.MeshProbeTests testProjectionReportsRecentSwaps]' started.
Test Case '-[GaiaFusionTests.MeshProbeTests testProjectionReportsRecentSwaps]' passed (0.000 seconds).
Test Suite 'MeshProbeTests' passed at 2026-04-10 11:23:12.383.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'PlantKindsCatalogTests' started at 2026-04-10 11:23:12.383.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testCanonicalKindsPassThrough]' started.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testCanonicalKindsPassThrough]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testLegacyAliasesResolveToCanonicalKinds]' started.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testLegacyAliasesResolveToCanonicalKinds]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testSharedCatalogNonEmpty]' started.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testSharedCatalogNonEmpty]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testUnknownKindRefused]' started.
Test Case '-[GaiaFusionTests.PlantKindsCatalogTests testUnknownKindRefused]' passed (0.000 seconds).
Test Suite 'PlantKindsCatalogTests' passed at 2026-04-10 11:23:12.384.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'SwapLifecycleTests' started at 2026-04-10 11:23:12.384.
Test Case '-[GaiaFusionTests.SwapLifecycleTests testExplicitSwapKindPassthrough]' started.
Test Case '-[GaiaFusionTests.SwapLifecycleTests testExplicitSwapKindPassthrough]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.SwapLifecycleTests testSwapLifecycleAdvances]' started.
Test Case '-[GaiaFusionTests.SwapLifecycleTests testSwapLifecycleAdvances]' passed (0.000 seconds).
Test Case '-[GaiaFusionTests.SwapLifecycleTests testSwapLifecycleStartsRequested]' started.
Test Case '-[GaiaFusionTests.SwapLifecycleTests testSwapLifecycleStartsRequested]' passed (0.000 seconds).
Test Suite 'SwapLifecycleTests' passed at 2026-04-10 11:23:12.384.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'GaiaFusionPackageTests.xctest' passed at 2026-04-10 11:23:12.384.
	 Executed 26 tests, with 0 failures (0 unexpected) in 0.199 (0.202) seconds
Test Suite 'All tests' passed at 2026-04-10 11:23:12.384.
	 Executed 26 tests, with 0 failures (0 unexpected) in 0.199 (0.203) seconds
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
REPORT_JSON: /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/RELEASE_REPORT_20260410T152114Z.json
REPORT_MD: /Users/richardgillespie/Documents/FoT8D/GAIAOS/evidence/fusion_control/RELEASE_REPORT_20260410T152114Z.md
