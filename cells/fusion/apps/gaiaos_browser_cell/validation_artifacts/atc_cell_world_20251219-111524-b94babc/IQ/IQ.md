# Installation Qualification (IQ)

Run ID: `atc_cell_world_20251219-111524-b94babc`
Artifacts base: `/Users/richardgillespie/Documents/FoT8D/cells/fusion/apps/gaiaos_browser_cell/validation_artifacts/atc_cell_world_20251219-111524-b94babc`

## Checks
- `GET /health` reachable (see `IQ/transport_health.json`)
- `GET /capabilities` reachable and includes `current_rev` (see `IQ/transport_capabilities.json`)
- `WS /ws/usd-deltas` reachable (UI connected screenshot stored in OQ/PQ)
- `/usd/state/live.usdc` HEAD recorded (see `IQ/live_usdc_head.txt`)

## Notes
- Degraded-but-honest is valid when `pxr_ok=false` and `usd_write_live_usdc=false`.
