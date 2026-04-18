# FINAL UI — ALL WORLDS

This is the entry point Rick should open first.

## Where are the docs?
- Final UI spec (behavior, controls, worlds, evidence requirements): `apps/gaiaos_browser_cell/doc/UI_ALL_WORLDS_FINAL.md`
- Runtime wiring / transport contract: `apps/gaiaos_browser_cell/docs/RUNTIME_WIRING.md`
- Truth vs perception contract: `apps/gaiaos_browser_cell/docs/PERCEPTION_VS_TRUTH.md`
- USD conversation mapping to UUM‑8D: `apps/gaiaos_browser_cell/docs/USD_CONVERSATIONS_UUM8D.md`

## One command (evidence bundle + hard-fail index)

From repo root:

```bash
export GAIAOS_RUN_ID="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
export BROWSER_CELL_BASE_URL="http://127.0.0.1:8896"
./apps/gaiaos_browser_cell/tests/playwright/helpers/run_iqoqpq_with_index.sh
```

Output:
- `apps/gaiaos_browser_cell/validation_artifacts/${GAIAOS_RUN_ID}/INDEX.md`


