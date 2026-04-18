# FINAL UI — ALL WORLDS

This is the human-readable, source-linked description of the **final working GaiaOS Browser Cell UI** and how to **prove it exists** with an evidence bundle that hard-fails if anything is missing.

## Runbook (one command)

### Prereqs
- Browser Cell stack reachable at the nginx UI port (default: `http://127.0.0.1:8896`)

### Evidence bundle (IQ/OQ/PQ + INDEX + diagnostics)

From repo root:

```bash
export GAIAOS_RUN_ID="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
export BROWSER_CELL_BASE_URL="http://127.0.0.1:8896"
./apps/gaiaos_browser_cell/tests/playwright/helpers/run_iqoqpq_with_index.sh
```

Artifacts appear at:
- `apps/gaiaos_browser_cell/validation_artifacts/${GAIAOS_RUN_ID}/INDEX.md`

How to interpret `INDEX.md`:
- It is the **single clickable entry point** to all evidence: IQ/OQ/PQ docs, per-world screenshots, and diagnostics.
- All link targets are `./relative/posix` paths and resolve inside the run folder.
- Generation hard-fails (exit code 3) if required artifacts are missing.

If the generator hard-fails:
- This is expected enforcement. The missing list printed in `diagnostics/index_generator.log` is the authoritative “what is missing” list.

## UI entrypoints (source of truth)

- **Browser UI HTML entrypoint**: `apps/gaiaos_browser_cell/web/index.html`
- **Nginx routing / proxy**: `apps/gaiaos_browser_cell/nginx/default.conf`
- **Cell discovery config**: `apps/gaiaos_browser_cell/public/cells.json`
- **Playwright evidence runner**: `apps/gaiaos_browser_cell/tests/playwright/`
  - Wrapper (official): `apps/gaiaos_browser_cell/tests/playwright/helpers/run_iqoqpq_with_index.sh`
  - Index generator: `apps/gaiaos_browser_cell/tests/playwright/helpers/build_index.ts`

## World model (what worlds exist)

The UI currently exposes these worlds (no other world selector exists in the shipped UI):
- **Cell**
- **Human**
- **Astro**

If “SmallWorlds”, “PDE view”, or a “4th view” is required, it must be added explicitly as a new world button and corresponding evidence requirements. As shipped today, the final working UI is the 3-world selector above.

## USD “conversation” (projection/perception loop)

If you expected “more happening” visually, the key is to look at the **USD conversation clock** (`rev`) and the **stream envelopes** (truth vs perception).

Read:
- `apps/gaiaos_browser_cell/docs/USD_CONVERSATIONS_UUM8D.md`

## Global UI behavior + controls

### How to enter the UI
- Open the Browser Cell URL (nginx): `http://127.0.0.1:8896/`

### Camera controls (OrbitControls)
- **Rotate**: left mouse drag
- **Pan**: right mouse drag (or trackpad equivalent)
- **Zoom**: mouse wheel / trackpad pinch

### Panels (what they are, what they do)

All panels are part of `apps/gaiaos_browser_cell/web/index.html`:

- **Status panel** (`#status`, top-right):
  - Connection state, current cell id, current world, per-world rev, WS message count, last resync timestamp, entity counts.
- **Provider panel** (`#provider-status`, top-left):
  - Shows enabled/disabled provider capability flags reported by `/capabilities`.
  - Cell selector (`#cell-select`) loads from `/public/cells.json`.
- **World switcher** (`#world-switcher`, bottom-left):
  - Buttons for **Cell**, **Human**, **Astro**.
  - Switch is UI-scoped: it changes the UI’s current view; it does not mutate truth.
- **Actions** (`#actions`, bottom-left):
  - **Annotate**: prompts for text; sends JSON perception op to `POST /perception`.
  - **Mark (Perception)**: prompts for a note; writes a perception-only mark under `/GaiaOS/Worlds/<World>/Perception/Marks/...` via `POST /perception`.
  - **Focus**: centers camera target on selected entity.
- **Inspector** (`#inspector`, bottom-right):
  - Shows selected entity metadata.
  - Explicitly displays `not_truth=true` for perception overlays.
- **Weather inspector** (`#weather-inspector`, bottom-right):
  - Shows METAR station data when selecting a weather station entity.
- **Alert banner** (`#alert-banner`, center):
  - Shown when a severe alert is received.

### Transport behavior (truth vs perception)
- The UI reads state via:
  - `GET /capabilities`
  - `WS /ws/usd-deltas` (truth ops envelope)
- The UI writes operator observations via:
  - `POST /perception` (JSON ops; broadcasts back as `perception_ops` with `not_truth=true`)

## Per-world documentation

### Cell world
1. Purpose
   - Visualize and interact with Cell-world entities and perception overlays.
2. How to enter it
   - Click the **Cell** button in the WORLDS panel.
3. Controls
   - Same global camera controls; selection via click.
4. UI panels
   - Same global panels; inspector shows selected entity metadata.
5. Data sources
   - Truth: WS deltas tagged `world=Cell`
   - Perception: UI-originated ops posted to `/perception`, broadcast back with `not_truth=true`
6. Evidence requirements
   - `ui_worlds/cell/views/default.png`
   - `ui_worlds/cell/views/zoomed.png`
   - `ui_worlds/cell/views/global.png`
   - `ui_worlds/cell/views/degraded_capability.png`
   - `ui_worlds/cell/functions/perception_mark.png`
7. Failure modes
   - Loading overlay never clears when the UI cannot load required JS modules or cannot connect to WS.
8. Source-of-truth file map
   - UI world switching: `apps/gaiaos_browser_cell/web/index.html` (WORLDS button handlers)
   - OQ evidence capture: `apps/gaiaos_browser_cell/tests/playwright/10_oq_cell_world.spec.ts`

### Human world (ATC / fields)
1. Purpose
   - Visualize Human-world entities and ATC/weather field objects (e.g., METAR stations and alerts).
2. How to enter it
   - Click the **Human** button in the WORLDS panel.
3. Controls
   - Same global camera controls; click selection.
4. UI panels
   - Weather inspector is used when selecting a weather station marker.
5. Data sources
   - Truth: WS deltas tagged `world=Human`, including field attribute updates under `/Worlds/Human/Fields/...`
6. Evidence requirements
   - `ui_worlds/human/views/default.png`
   - `ui_worlds/human/views/zoomed.png`
   - `ui_worlds/human/views/global.png`
   - `ui_worlds/human/views/degraded_capability.png`
   - `ui_worlds/human/functions/perception_mark.png`
7. Failure modes
   - Severe alert banner can cover the screen; close with the Close button.
8. Source-of-truth file map
   - Field handling (METAR/alerts): `apps/gaiaos_browser_cell/web/index.html` (`handleMetarUpdate`, `handleAlertUpdate`)
   - OQ evidence capture: `apps/gaiaos_browser_cell/tests/playwright/11_oq_human_world.spec.ts`

### Astro world
1. Purpose
   - Visualize Astro-world entities and perception overlays.
2. How to enter it
   - Click the **Astro** button in the WORLDS panel.
3. Controls
   - Same global camera controls; click selection.
4. UI panels
   - Same global panels.
5. Data sources
   - Truth: WS deltas tagged `world=Astro`
   - Perception: UI-originated ops posted to `/perception`, broadcast back with `not_truth=true`
6. Evidence requirements
   - `ui_worlds/astro/views/default.png`
   - `ui_worlds/astro/views/zoomed.png`
   - `ui_worlds/astro/views/global.png`
   - `ui_worlds/astro/views/degraded_capability.png`
   - `ui_worlds/astro/functions/perception_mark.png`
7. Failure modes
   - Loading overlay never clears when required JS modules cannot be loaded.
8. Source-of-truth file map
   - OQ evidence capture: `apps/gaiaos_browser_cell/tests/playwright/12_oq_astro_world.spec.ts`

## “Stopping” diagnosis (what it looked like, what fixed state looks like)

### Stop symptom
- UI stays in **“Connecting to GaiaOS…”** with the loading overlay visible (`#loading` never becomes hidden).
- Playwright evidence: the test times out waiting for `#loading` to be hidden.

### Root cause (fixed)
- The UI’s import map previously loaded Three.js modules from an external CDN.
- When outbound network to the CDN is blocked or flaky, the module import fails and the UI cannot initialize.

### Fix (applied)
- Vendored Three.js modules inside the repo under:
  - `apps/gaiaos_browser_cell/public/vendor/three/`
- Updated `apps/gaiaos_browser_cell/web/index.html` import map to use local `/public/vendor/...` paths.
- Added an explicit stop-reproduction Playwright test (gated by `GAIAOS_REPRO_STOP=1`) to prove the UI loads even with CDN blocked:
  - `apps/gaiaos_browser_cell/tests/playwright/05_repro_stop_cdn_block.spec.ts`


