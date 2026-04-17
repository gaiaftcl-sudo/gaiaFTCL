# Witness: Phase 0 gate + strict context validate (FoF spine continuation)

**UTC:** 2026-04-05 (Phase 0 `generated_at_utc`: **2026-04-05T16:23:15Z**)  
**GAIA_ROOT:** `/Users/richardgillespie/Documents/FoT8D/GAIAOS`  
**Git SHA:** `5729f829de92bf819c217d586e6601daec9c1631`

## 1. Phase 0 gate (full, with Playwright Track E2)

```bash
cd /Users/richardgillespie/Documents/FoT8D/GAIAOS
FUSION_PHASE0_E2E=1 GAIA_ROOT=/Users/richardgillespie/Documents/FoT8D/GAIAOS bash scripts/fusion_phase0_gate.sh
```

**Result:** exit **0** — `CALORIE: phase0_gate green`  
**Report:** `evidence/fusion_control/phase0_gate/REPORT.json` (`schema: gaiaftcl_fusion_phase0_gate_report_v2`)  
**`overall_ok`:** **true**  
**Failed steps:** **none**

### Skipped (do not block `overall_ok` per script)

| Track | Note |
|-------|------|
| E3 | Soak — `set FUSION_PHASE0_SOAK=1 for soak report` |
| E4 | Long-run tail — `set FUSION_PHASE0_LONG_RUN_LINES=N for tail witness` |
| G1 | Discord slash receipt file — manual `/fusion_fleet`; optional evidence path |

### Passed highlights (sample)

- **A1:** `scope_fortress_scan.sh`
- **B:** `cell_identity.json`, valid `cell_id`, `mount_receipt.json`
- **C:** Moor state file present; schema / `last_mesh_ok_utc` / `cell_id` alignment; freshness vs `mesh_heartbeat_max_sec`
- **D:** Moor preflight + D2 negative restore path
- **E1:** `preflight_fusion_ui_live.sh`
- **E2:** `npm run test:e2e:fusion` (Playwright fusion suite)
- **F1–F3:** `curl` fleet-digest, fleet-usd, s4-projection on `http://127.0.0.1:8910`

## 2. Fusion context validate (STRICT=1)

```bash
STRICT=1 GAIA_ROOT=/Users/richardgillespie/Documents/FoT8D/GAIAOS bash scripts/fusion_context_validate.sh
```

**Result:** exit **0** — `Terminal state: CALORIE`

Checks satisfied:

- `~/.gaiaftcl/cell_identity.json` present
- `REPORT.json` exists and `overall_ok=true`
- `GET http://127.0.0.1:8910/api/fusion/fleet-digest` → **HTTP 200**
- Docker volume matching `*fusion_fleet_evidence*` exists

## 3. B7 — fleet snapshot (closed local loop, 2026-04-05)

**Status:** **CALORIE** — see `FLEET_SNAPSHOT_B7_WITNESS_20260405.md` and `evidence/fusion_control/fusion_fleet_snapshot.json`. `fusion_cell_status_nats_publish.sh` now prefers **`nats-py`** when the `nats` CLI / Docker box cannot reach the broker.

**Carry:** run the same **subscriber** on **mesh head** against prod NATS (compose/deploy limb).

## 4. Relation to prior witness

- **`TEST_FUSION_ALL_WITNESS_20260405T162023Z.*`** — `npm run test:fusion:all` including dual Discord + MCP preflight (mesh-head fallback).
- This file — **Phase 0 A–G gate** + **STRICT context** on same host where Fusion UI answers on **:8910**.

**FoF (update):** Re-ran Phase 0 with **`FUSION_PHASE0_SOAK=1`** + **`FUSION_PHASE0_LONG_RUN_LINES=5`** + **`FUSION_PHASE0_E2E=1`** → **`overall_ok: true`**; only **G1** (manual Discord slash receipt) remains **skipped** (non-blocking per `fusion_phase0_gate.sh`). B7 local snapshot closed (see §3).

## 5. Discord mesh digest evidence (same session)

`FUSION_DIGEST_SAVE_EVIDENCE=1 FUSION_SOVEREIGN_UI_URL=http://127.0.0.1:8910 bash scripts/fusion_discord_challenge_digest.sh` → saved:

- `evidence/fusion_control/discord_mesh_digest/global-challenge-digest_20260405T162513Z.json`
- `mesh-operator-spine_20260405T162513Z.json`
- `s4-projection_20260405T162513Z.json`
- `digest_manifest_20260405T162513Z.jsonl`
