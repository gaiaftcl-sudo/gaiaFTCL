## UUM-8D Broker (GaiaOS)

Evidence-first, SaaS-free node-to-node messaging:

- WebSocket peer links (`GET /ws` with `x-node-id`)
- ArangoDB durable queue (collections: `messages_pending`, `messages_delivered`, `messages_failed`)
- Ed25519 signing over `"{id}:{payload_hash_hex}"`
- Blake3 hash over compressed `content_bytes`
- zstd compression for content payloads

### Run (local)

Environment:

```bash
export NODE_ID="hetzner-node-1"
export BIND_ADDR="0.0.0.0:9001"
export ARANGO_URL="http://127.0.0.1:8529"
export ARANGO_USER="root"
export ARANGO_PASS="password"
export ARANGO_DB="uum8d_comms"
# Optional key persistence (32-byte seed file). If the path does not exist, it will be created.
export KEYPAIR_SEED_PATH="/data/keys/uum8d_broker_seed.bin"
# Optional mesh dial-out (comma-separated):
# - "peerId=host:9001,peerId2=host2:9001"
# - or "host:9001,host2:9001"
export PEER_ENDPOINTS="cell-2=cell-2-ip:9001,cell-3=cell-3-ip:9001"
```

Run:

```bash
cargo run -p uum8d_broker
```

### Docker compose overlay

This repo includes two overlays at the repo root:

- `docker-compose.uum8d-broker.yml`: expects an `arangodb` service present in the compose stack (dev/single-host)
- `docker-compose.uum8d-broker.external-arango.yml`: targets an external ArangoDB endpoint (production/Hetzner-ready)

Layer onto any existing compose:

```bash
docker compose -f docker-compose.yml -f docker-compose.uum8d-broker.yml up -d
```

Or external ArangoDB:

```bash
export UUM8D_ARANGO_URL="http://<ARANGO_HOST>:8529"
docker compose -f docker-compose.yml -f docker-compose.uum8d-broker.external-arango.yml up -d
```

### ArangoDB initialization

An `arangosh` init script is provided in `services/uum8d_broker/arango/`:

- `services/uum8d_broker/arango/init_uum8d_comms.js`
- `services/uum8d_broker/arango/README.md`

### API

- `GET /health` → `200 ok`
- `GET /ws` → WebSocket upgrade; include header `x-node-id: <remote_node_id>`
- `POST /send` → JSON body:
  - `to_node`: string
  - `priority`: `Critical|High|Normal|Low` (optional)
  - `flow`: `Direct|Broadcast|ConstitutionalChain|EventStream` (optional)
  - `ttl_seconds`: number (optional)
  - `body`: JSON object (compressed + signed)


