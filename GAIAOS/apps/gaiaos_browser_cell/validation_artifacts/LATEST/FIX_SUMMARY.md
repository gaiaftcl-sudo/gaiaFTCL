# Fix Summary

## Symptom ("it stops")
- UI remained on the loading overlay ("Connecting to GaiaOS...") and did not become interactive.
- Playwright evidence was a timeout waiting for `#loading` to be hidden.

## Root cause
- `apps/gaiaos_browser_cell/web/index.html` imported Three.js modules from an external CDN.
- When the environment blocks outbound network (or the CDN is flaky), the JS module import fails and the UI cannot initialize.

## Fix applied
- Vendored Three.js modules locally:
  - `apps/gaiaos_browser_cell/public/vendor/three/three.module.js`
  - `apps/gaiaos_browser_cell/public/vendor/three/addons/controls/OrbitControls.js`
  - `apps/gaiaos_browser_cell/public/vendor/three/addons/renderers/CSS2DRenderer.js`
- Updated the UI import map to use local `/public/vendor/...` paths.
- Added a deterministic reproduction test (gated by `GAIAOS_REPRO_STOP=1`) that blocks external CDN URLs and asserts the UI still loads:
  - `apps/gaiaos_browser_cell/tests/playwright/05_repro_stop_cdn_block.spec.ts`

## Files changed
- `apps/gaiaos_browser_cell/web/index.html`
- `apps/gaiaos_browser_cell/public/vendor/three/**`
- `apps/gaiaos_browser_cell/tests/playwright/05_repro_stop_cdn_block.spec.ts`
- `apps/gaiaos_browser_cell/tests/playwright/helpers/run_iqoqpq_with_index.sh`
- `apps/gaiaos_browser_cell/tests/playwright/helpers/build_index.ts`
- `apps/gaiaos_browser_cell/tests/playwright/helpers/diagnostics.ts`
- `apps/gaiaos_browser_cell/tests/playwright/helpers/har_probe.js`
- `apps/gaiaos_browser_cell/tests/playwright/playwright.config.ts`
- `apps/gaiaos_browser_cell/tests/playwright/global-teardown.ts`

## How to verify

### 1) Run the evidence bundle
```bash
export GAIAOS_RUN_ID="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
export BROWSER_CELL_BASE_URL="http://127.0.0.1:8896"
./apps/gaiaos_browser_cell/tests/playwright/helpers/run_iqoqpq_with_index.sh
```

### 2) Prove the stop is fixed under CDN-blocked conditions
```bash
export GAIAOS_REPRO_STOP=1
export GAIAOS_RUN_ID="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
export BROWSER_CELL_BASE_URL="http://127.0.0.1:8896"
./apps/gaiaos_browser_cell/tests/playwright/helpers/run_iqoqpq_with_index.sh
```
