# Performance Qualification (PQ)

Run: `modern_atc_streams_danger_20251219-130141-277f596`

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
