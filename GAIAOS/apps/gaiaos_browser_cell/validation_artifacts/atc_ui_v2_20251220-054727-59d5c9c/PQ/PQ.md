# Performance Qualification (PQ)

Run: `atc_ui_v2_20251220-054727-59d5c9c`

## Scenarios tested
- Sustained WS traffic (perception ops) while UI is active
- Forced WS disconnect (debug hook)
- Automatic reconnect + resync (capabilities refresh)

## Evidence
- Screenshots:
  - `PQ/sustained_ws_msgs.png`
  - `PQ/ws_resync_connected.png`
- Capabilities snapshot:
  - `PQ/capabilities_after_resync.json`
