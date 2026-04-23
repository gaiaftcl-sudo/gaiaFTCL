# `mac_cell_bridge` (MVP)

**Role:** prove **NATS** connectivity from the Mac lane with a **real** publish to one fixed subject. This is a **liveness** check, not GAMP5 evidence and not a second receipt store.

**Build (from repository root, workspace member):**

```bash
cd /path/to/FoT8D
cargo build -p mac_cell_bridge --release
```

**Run (requires a reachable NATS on `NATS_URL`, default `nats://127.0.0.1:4222`):**

```bash
NATS_URL=nats://127.0.0.1:4222 ./target/release/mac_cell_bridge
```

**Subject:** `gaiaftcl.mac_cell_bridge.liveness` — JSON body `ok`, `ts` (RFC3339), `component`.

**Out of scope (v0):** Arango streaming, PoL, envelope FSM, JetStream durable consumers.

See [../../docs/LIVE_CELL_GAMES.md](../../docs/LIVE_CELL_GAMES.md) and the MacFranklin Expert Cell plan (Appendix B).
