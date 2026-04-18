# Installation Qualification (IQ)

Run ID: `global_atc_20251220-061528-89c7e26`
Artifacts base: `/Users/richardgillespie/Documents/FoT8D/cells/fusion/apps/gaiaos_browser_cell/validation_artifacts/global_atc_20251220-061528-89c7e26`

## Checks
- `GET /health` reachable (see `IQ/transport_health.json`)
- `GET /capabilities` reachable and includes `current_rev` (see `IQ/transport_capabilities.json`)
- `WS /ws/usd-deltas` reachable (UI connected screenshot stored in OQ/PQ)
- `/usd/state/live.usdc` HEAD recorded (see `IQ/live_usdc_head.txt`)

## Notes
- Degraded-but-honest is valid when `pxr_ok=false` and `usd_write_live_usdc=false`.
