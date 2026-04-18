# B7 witness — `fusion_fleet_snapshot.json` (local NATS loop)

**UTC:** 2026-04-05 (~16:29Z publish)  
**GAIA_ROOT:** `/Users/richardgillespie/Documents/FoT8D/GAIAOS`  
**NATS:** `nats://127.0.0.1:4222`

## CURE path (this limb)

1. **`scripts/fusion_cell_status_nats_publish.sh`** — was failing with `nats` CLI / `nats-box` (“no servers available”) while **`nats-py`** connected cleanly. **CURE:** script now **prefers `nats-py`** for publish when import succeeds.
2. **Subscriber:** `python3 scripts/fusion_fleet_snapshot_subscriber.py` (background) + **publish** → merged snapshot file.

## Receipt

- **Publish:** `CALORIE: published gaiaftcl.fusion.cell.status.v1 (436 bytes) cell_id=<cell_identity>`
- **File:** `evidence/fusion_control/fusion_fleet_snapshot.json`
  - `schema`: `gaiaftcl_fusion_fleet_snapshot_v1`
  - `updated_at_utc`: `2026-04-05T16:29:55Z`
  - `cells`: one key matching `cell_identity.json`

## Ops note (nine-cell)

Mesh **head** should run the same subscriber against **production** NATS; this witness proves **subject + merge + file** on a **Mac leaf** with a reachable local broker. **Not** a substitute for head-cell compose unless the same process is deployed there.

## Terminal

**CLOSURE: CALORIE** — B7 **local** C⁴ file witness + publish path **CURE** (nats-py preference).
