# UI SURFACE INVENTORY

**Purpose:** Complete enumeration of existing UI surfaces (routes, panels, components) in the Browser Cell.

**Branch:** phase-a-baseline  
**Date:** 2026-01-31  
**Source:** `apps/gaiaos_browser_cell/doc/UI_ALL_WORLDS_FINAL.md`

---

## PRIMARY UI ENTRYPOINT

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| BROWSER_CELL_ROOT | `/` (nginx port 8896) | index.html | WebSocket `/ws/usd-deltas`, GET `/capabilities` | `apps/gaiaos_browser_cell/web/index.html` |

---

## WORLD VIEWS (3 WORLDS)

**World Switcher:** `#world-switcher` (bottom-left panel)

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| WORLD_CELL | `/` (world=Cell) | World switcher button, 3D scene | WS `/ws/usd-deltas` (Cell world USD) | `apps/gaiaos_browser_cell/web/index.html` (world switcher) |
| WORLD_HUMAN | `/` (world=Human) | World switcher button, 3D scene | WS `/ws/usd-deltas` (Human world USD) | `apps/gaiaos_browser_cell/web/index.html` (world switcher) |
| WORLD_ASTRO | `/` (world=Astro) | World switcher button, 3D scene | WS `/ws/usd-deltas` (Astro world USD) | `apps/gaiaos_browser_cell/web/index.html` (world switcher) |

**Note:** World switching is UI-scoped only; it does not mutate truth.

---

## PANELS (ALL IN index.html)

### Status Panel

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| STATUS_PANEL | `/` | `#status` (top-right) | WS `/ws/usd-deltas`, connection state, cell id, world, rev, message count, resync timestamp, entity counts | `apps/gaiaos_browser_cell/web/index.html:70-71` |

### Provider Panel

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| PROVIDER_PANEL | `/` | `#provider-status` (top-left) | GET `/capabilities` (provider capability flags) | `apps/gaiaos_browser_cell/web/index.html:72-74` |
| CELL_SELECTOR | `/` | `#cell-select` (within provider panel) | GET `/public/cells.json` | `apps/gaiaos_browser_cell/web/index.html:74` |

### World Switcher Panel

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| WORLD_SWITCHER_PANEL | `/` | `#world-switcher` (bottom-left) | Buttons: Cell, Human, Astro | `apps/gaiaos_browser_cell/web/index.html:75-77` |

### Actions Panel

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| ACTIONS_PANEL | `/` | `#actions` (bottom-left) | POST `/perception` (Annotate, Mark, Focus actions) | `apps/gaiaos_browser_cell/web/index.html:78-81` |

**Actions:**
- **Annotate:** Prompts for text; sends JSON perception op to POST `/perception`
- **Mark (Perception):** Prompts for note; writes perception-only mark under `/GaiaOS/Worlds/<World>/Perception/Marks/...`
- **Focus:** Centers camera target on selected entity

### Inspector Panel

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| INSPECTOR_PANEL | `/` | `#inspector` (bottom-right) | Selected entity metadata, `not_truth=true` flag for perception overlays | `apps/gaiaos_browser_cell/web/index.html:82-84` |

### Weather Inspector Panel

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| WEATHER_INSPECTOR_PANEL | `/` | `#weather-inspector` (bottom-right) | METAR station data (when weather station entity selected) | `apps/gaiaos_browser_cell/web/index.html:85-86` |

### Alert Banner

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| ALERT_BANNER | `/` | `#alert-banner` (center) | Severe alert messages from WS `/ws/usd-deltas` | `apps/gaiaos_browser_cell/web/index.html:87-88` |

---

## CAMERA CONTROLS (OrbitControls)

**Not a UI panel, but a global interaction surface:**

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| CAMERA_CONTROLS | `/` | OrbitControls (Three.js) | Mouse/trackpad input | `apps/gaiaos_browser_cell/web/index.html` (implicit) |

**Controls:**
- **Rotate:** Left mouse drag
- **Pan:** Right mouse drag (or trackpad equivalent)
- **Zoom:** Mouse wheel / trackpad pinch

---

## TRANSPORT ENDPOINTS

**Read (Truth):**
- `GET /capabilities` - Provider capability flags
- `WS /ws/usd-deltas` - Truth ops envelope (USD delta stream)

**Write (Perception):**
- `POST /perception` - JSON ops (broadcasts back as `perception_ops` with `not_truth=true`)

---

## ROUTING / PROXY

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| NGINX_PROXY | `/` (all routes) | Nginx reverse proxy | Upstream services | `apps/gaiaos_browser_cell/nginx/default.conf` |

---

## CELL DISCOVERY CONFIG

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| CELLS_CONFIG | `/public/cells.json` | Cell registry JSON | Static file | `apps/gaiaos_browser_cell/public/cells.json` |

---

## PLAYWRIGHT EVIDENCE RUNNER

| ui_surface_id | route | primary_components | data_sources | source_path |
|---------------|-------|-------------------|--------------|-------------|
| PLAYWRIGHT_RUNNER | N/A (test harness) | Playwright test suite | Browser Cell UI | `apps/gaiaos_browser_cell/tests/playwright/` |
| IQOQPQ_WRAPPER | N/A (test harness) | Shell script wrapper | Playwright runner | `apps/gaiaos_browser_cell/tests/playwright/helpers/run_iqoqpq_with_index.sh` |
| INDEX_GENERATOR | N/A (test harness) | TypeScript index builder | Evidence artifacts | `apps/gaiaos_browser_cell/tests/playwright/helpers/build_index.ts` |

---

## SUMMARY

**Total UI Surfaces:** 15 (excluding test harness)

**World Views:** 3 (Cell, Human, Astro)

**Panels:** 7 (Status, Provider, World Switcher, Actions, Inspector, Weather Inspector, Alert Banner)

**Global Controls:** 1 (Camera/OrbitControls)

**Transport:** 3 endpoints (GET /capabilities, WS /ws/usd-deltas, POST /perception)

**Config:** 1 (cells.json)

**Routing:** 1 (Nginx proxy)

---

**VERIFICATION COMMAND:**

```bash
rg "#status|#provider-status|#world-switcher|#actions|#inspector|#weather-inspector|#alert-banner" apps/gaiaos_browser_cell/web/index.html
```

---

**END OF INVENTORY**
