### GaiaOS Browser Cell (Production Layout)

This directory is the **production layout** for the GaiaOS Browser Client UI cell + its local `USD_TransportCell` (transport + audit + perception ingress).

## FINAL UI DOCS + EVIDENCE (CLICK)

- `OPEN_THESE_DOCS_FIRST.md`
- `doc/BROWSER_CELL_UI_FINAL.md`
- `apps/gaiaos_browser_cell/doc/UI_ALL_WORLDS_FINAL.md`
- `apps/gaiaos_browser_cell/validation_artifacts/LATEST/INDEX.md`

## Where are the docs?

### FINAL UI — ALL WORLDS
- `doc/BROWSER_CELL_UI_FINAL.md`
- `apps/gaiaos_browser_cell/doc/UI_ALL_WORLDS_FINAL.md`

- **Staging sandbox** remains in `review/` (do not treat `review/` as prod).
- **Playwright proof** targets this app by default.

### Run (local dev)

```bash
cd apps/gaiaos_browser_cell
cp env.example .env
docker compose up --build -d
```

### Flatcar deployment

See: `docs/FLATCAR_DEPLOYMENT.md`

### Contracts (read first)

- `docs/PERCEPTION_VS_TRUTH.md`
- `docs/RUNTIME_WIRING.md`
- `docs/SPATIAL_AUDIO.md`

### Profiles

- **single-cell**: includes local `arangodb` container (default via `COMPOSE_PROFILES=single-cell` in `env.example`)
- **multi-cell**: runs without `arangodb` container; you must set `ARANGO_URL` to a reachable ArangoDB
- **monitoring**: adds Prometheus + Grafana

Examples:

```bash
# Single-cell (default)
docker compose up -d

# Multi-cell (no local ArangoDB)
COMPOSE_PROFILES=multi-cell docker compose up -d

# Multi-cell + monitoring
COMPOSE_PROFILES=multi-cell,monitoring docker compose up -d
```

Open:

- UI: `http://127.0.0.1:${GAIAOS_BROWSER_CELL_PORT:-8896}/`
  - Port comes from `UI_PORT` in `.env` (defaults to 8896 in `env.example`)

### Validate (proof gates)

```bash
python3 scripts/validate_usd_browser_cell.py --base http://127.0.0.1:${GAIAOS_BROWSER_CELL_PORT:-8896}
```

### UI screenshot proof (Playwright)

From repo root:

```bash
npx playwright test --project=browser-cell-ui
```

Override base URL:

```bash
BROWSER_CELL_BASE_URL=http://127.0.0.1:${GAIAOS_BROWSER_CELL_PORT:-8896} npx playwright test --project=browser-cell-ui
```

### IQ/OQ/PQ evidence run (Playwright-owned)

This generates:

```
apps/gaiaos_browser_cell/validation_artifacts/<run_id>/
  IQ/
  OQ/
  PQ/
  ui_worlds/
  meta/
```

Run:

```bash
export GAIAOS_RUN_ID="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
export BROWSER_CELL_BASE_URL="http://127.0.0.1:${UI_PORT:-8896}"
./apps/gaiaos_browser_cell/tests/playwright/helpers/run_iqoqpq_with_index.sh
```

Output:

- `apps/gaiaos_browser_cell/validation_artifacts/${GAIAOS_RUN_ID}/INDEX.md`

Direct `npx playwright test` invocations are unsupported for IQ/OQ/PQ runs because they may not generate a compliant `INDEX.md`.


