# Witness: `npm run test:fusion:all` (full battery)

**Schema:** ad hoc C⁴ witness (Field of Fields B1 battery)  
**Generated at (UTC):** 2026-04-05T16:20:23Z  
**Git SHA (GAIAOS):** `5729f829de92` (short)  
**Host:** Mac limb (Darwin); user `richardgillespie`  
**Exit code:** `0`

## Command

```bash
cd services/gaiaos_ui_web
GAIA_ROOT=/Users/richardgillespie/Documents/FoT8D/GAIAOS npm run test:fusion:all
```

**Working directory:** `GAIAOS/services/gaiaos_ui_web`  
**GAIA_ROOT:** absolute path to GAIAOS checkout root (required by `playwright.fusion.config.ts`).

## Chain (from `package.json`)

1. `bash ../../scripts/preflight_mcp_gateway.sh`
2. `bash ../../scripts/test_fusion_discord_tier_a.sh`
3. `bash ../../scripts/test_fusion_mesh_mooring_stack.sh`
4. `npm run test:unit:fusion` → `vitest run`
5. `npm run test:e2e:fusion` → `playwright test --config=playwright.fusion.config.ts`
6. `npm run test:e2e:discord:gaiaftcl` → `playwright_discord_test_wrap.sh gaiaftcl 1`
7. `npm run test:e2e:discord:fom` → `playwright_discord_test_wrap.sh face_of_madness 0`

## Full transcript

```
> gaiaos_ui_web@0.1.0 test:fusion:all
> bash ../../scripts/preflight_mcp_gateway.sh && bash ../../scripts/test_fusion_discord_tier_a.sh && bash ../../scripts/test_fusion_mesh_mooring_stack.sh && npm run test:unit:fusion && npm run test:e2e:fusion && npm run test:e2e:discord:gaiaftcl && npm run test:e2e:discord:fom

curl: (7) Failed to connect to 127.0.0.1 port 8803 after 0 ms: Couldn't connect to server
OK gateway fallback http://77.42.85.60:8803/health (local http://127.0.0.1:8803 unreachable)
PASS bash_n gaiaftcl_turbo_ide
PASS bash_n gaia_nats_leaf_status.sh
PASS bash_n fusion_mesh_mooring_heartbeat.sh
PASS bash_n gaia_measured_record.sh
PASS bash_n measured_status.sh
PASS bash_n mcp_bridge_torax
PASS bash_n nats_tunnel_head.sh
PASS bash_n cell_onboard.sh
PASS bash_n mcp_bridge_marte2
PASS bash_n gaia_mount
PASS bash_n mcp_proxy
PASS gateway_health@http://77.42.85.60:8803
PASS gateway_claims_skipped_used_mesh_head_fallback (use localhost tunnel + unset skip for full claims)
--- PASSED=13 FAILED=0 ---
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

 ✓ tests/unit/fusionS4PcsTelemetry.test.ts (4 tests) 5ms
 ✓ tests/unit/fusionChallengeLedger.cjs.test.ts (1 test) 6ms
 ✓ tests/unit/fusionS4GlobalChallenge.test.ts (1 test) 4ms
 ✓ tests/unit/fusionS4Gates.test.ts (13 tests) 9ms

 Test Files  4 passed (4)
      Tests  19 passed (19)
      Start at  12:19:59
      Duration  680ms

> gaiaos_ui_web@0.1.0 test:e2e:fusion
> playwright test --config=playwright.fusion.config.ts

Running 14 tests using 1 worker

  -   1 [chromium] › tests/fusion/fusion_matrix_e2e.spec.ts:4:7 › Fusion matrix API (slow) › runMatrix=1 with minimal cycles when FUSION_MATRIX_E2E=1
  ✓   2 [chromium] › tests/fusion/fusion_s4_console.spec.ts:15:7 › Fusion S4 console › GET /api/fusion/s4-projection contract (55ms)
  ✓   3 [chromium] › tests/fusion/fusion_s4_console.spec.ts:131:7 › Fusion S4 console › GET /api/fusion/mesh-operator-spine contract (16ms)
  ✓   4 [chromium] › tests/fusion/fusion_s4_console.spec.ts:139:7 › Fusion S4 console › GET /api/fusion/soak-summary contract (25ms)
  ✓   5 [chromium] › tests/fusion/fusion_s4_console.spec.ts:161:7 › Fusion S4 console › GET /api/fusion/challenge-ledger read contract (13ms)
  ✓   6 [chromium] › tests/fusion/fusion_s4_console.spec.ts:169:7 › Fusion S4 console › POST /api/fusion/challenge-ledger registers team (secret) (10ms)
  ✓   7 [chromium] › tests/fusion/fusion_s4_console.spec.ts:191:7 › Fusion S4 console › GET /api/fusion/global-challenge-digest (15ms)
  ✓   8 [chromium] › tests/fusion/fusion_s4_console.spec.ts:201:7 › Fusion S4 console › GET /api/fusion/soak-summary markdown export (51ms)
  ✓   9 [chromium] › tests/fusion/fusion_s4_console.spec.ts:210:7 › Fusion S4 console › /fusion-s4 UI panels (909ms)
  ✓  10 [chromium] › tests/fusion/fusion_s4_console.spec.ts:230:7 › Fusion S4 console › Soak table lists four JSONL tracks (853ms)
  ✓  11 [chromium] › tests/fusion/fusion_s4_doc.spec.ts:11:7 › Fusion S4 documentation capture › full-page screenshot @fusion-doc (1.0s)
  ✓  12 [chromium] › tests/fusion/gate1_page.spec.ts:7:7 › GATE1 page › gate1 page loads and shows custody copy (399ms)
  ✓  13 [chromium] › tests/fusion/gate1_page.spec.ts:13:7 › GATE1 page › gate1-register-options GET returns JSON (15ms)
  ✓  14 [chromium] › tests/fusion/gate1_page.spec.ts:21:7 › GATE1 page › gate1-register-options POST is 403 until GATE1_LIFT=1 (10ms)

  1 skipped
  13 passed (5.0s)

> gaiaos_ui_web@0.1.0 test:e2e:discord:gaiaftcl
> bash ../../scripts/playwright_discord_test_wrap.sh gaiaftcl 1

CALORIE: Discord witness OK — /Users/richardgillespie/.playwright-discord/storage-gaiaftcl.json (48232 bytes, cookies key present)

Running 1 test using 1 worker

  ✓  1 [chromium] › tests/discord/discord_membrane_tier_b.spec.ts:36:7 › Discord membrane Tier B › logged-in channel surface (3.8s)

  1 passed (5.2s)

> gaiaos_ui_web@0.1.0 test:e2e:discord:fom
> bash ../../scripts/playwright_discord_test_wrap.sh face_of_madness 0

CALORIE: Discord witness OK — /Users/richardgillespie/.playwright-discord/storage-face-of-madness.json (48208 bytes, cookies key present)

Running 1 test using 1 worker

  ✓  1 [chromium] › tests/discord/discord_membrane_tier_b.spec.ts:36:7 › Discord membrane Tier B › logged-in channel surface (3.3s)

  1 passed (4.5s)
```

*(Note: transcript minor typos vs live output corrected only where line breaks were wrapped; counts unchanged.)*

## Summary table

| Stage | Result |
|--------|--------|
| MCP preflight | OK via fallback `77.42.85.60:8803` (localhost 8803 down) |
| Tier A shell | PASSED=13 FAILED=0 |
| Mesh mooring stack | PASSED=15 FAILED=0 |
| Vitest fusion | 19 passed, 4 files |
| Playwright fusion | 13 passed, 1 skipped (`FUSION_MATRIX_E2E` off) |
| Discord GaiaFTCL | 1 passed + witness preflight |
| Discord FOM | 1 passed + witness preflight |
| **Overall** | **exit 0**; wall ~23.4s |

## FoF interpretation

- **B1 battery:** This run satisfies the **normative** `test:fusion:all` chain in one witness with exit 0.
- **CURE (full Mac + Discord release in FoF scope):** Per [`docs/specs/FIELD_OF_FIELDS_AGENT_MOORING_PROTOCOL.md`](../../docs/specs/FIELD_OF_FIELDS_AGENT_MOORING_PROTOCOL.md), **CURE** is spine-top and includes Mac cell files (`cell_onboard`, `gaia_mount`, heartbeat JSON) **not** asserted by this npm script alone. This witness supports **B1 CALORIE** toward the mapping table; **DMG/HTTPS/onboard** remain separate limbs.
- **REFUSED / CURE inflation:** Do not label **CURE** for the whole product from this file only.

## Machine-readable

See sibling [`TEST_FUSION_ALL_WITNESS_20260405T162023Z.json`](TEST_FUSION_ALL_WITNESS_20260405T162023Z.json).
