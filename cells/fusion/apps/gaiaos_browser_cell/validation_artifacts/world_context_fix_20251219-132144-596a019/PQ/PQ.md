# Performance Qualification (PQ)

Run: `world_context_fix_20251219-132144-596a019`

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
