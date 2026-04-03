# Performance Qualification (PQ)

Run: `atc_safety_rss_20251220-080640-6012034`

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
