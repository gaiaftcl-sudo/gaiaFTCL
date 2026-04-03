### USD Conversations → Projection/Perception Loop → UUM‑8D Mapping

This is the **exact, standards-based “conversation”** between:
- **World truth** (WorldCells / substrate frames)
- **USD projection** (HTTP USD layers + WS delta envelopes)
- **Operator/UI perception** (append-only perception ops/layers, explicitly not truth)
- **UUM‑8D** (8D state update + FoT/virtue/truth/potential/psi dimensions)

This doc is intentionally mechanical: **message shapes, invariants, and wiring points**.

---

## What you’re seeing in the UI (why it feels “empty”)

If you see a grid + panels but no moving entities:
- The **transport loop is alive**, but it may be receiving **no new substrate frames**, so truth is not changing.
- Perception ops still work (Mark/Annotate), but they create **perception overlays** (orange spheres) and increment rev.
- Many attributes written by truth polling are **metadata-only** (e.g., `gaiaos:space`, `gaiaos:time`, `gaiaos:energy`, `gaiaos:consciousness`) and the current Three.js UI intentionally renders a minimal geometry placeholder per entity. If substrate frames are sparse/unchanging you’ll see no visual motion.

Hard proof of “conversation” exists even when visuals are static:
- `GET /capabilities` shows `current_rev` per world
- `POST /perception` bumps `current_rev[world]` and writes append-only files + audit events

---

## Transport surfaces (the USD conversation channels)

### 1) HTTP: authoritative USD layers (audit/replay)
Served by nginx → `usd-transport-cell`:
- `GET /usd/root.usda`
- `GET /usd/worlds/{cell,human,astro}.usda`
- `GET /usd/state/live.usd[a|c]`
- `GET /usd/artifacts/...` (raw upstream provider payloads when enabled)

**Contract**: HTTP layers are the auditable baseline. WS is best-effort.

### 2) WebSocket: best-effort live deltas (nervous system)
- `WS /ws/usd-deltas`

This is **not** “USD bytes over WS”. It is **USD‑representable ops** in a delta envelope.

### 3) Perception ingress: operator → cell
- `POST /perception` (JSON ops)
- `POST /usd/perception-layer` (USD overlay bytes, stored append-only)

Perception is persisted and broadcast back to observers as `not_truth=true`.

---

## Envelope schemas (exact shapes)

All envelopes include `cell_id`, `world`, `rev`, `ts`.

### Tick envelope (WS heartbeat)
Emitted periodically by the TransportCell to prove liveness even when no new truth/perception ops arrive.

**Important**: `tick` does **not** bump `rev` and does **not** claim any state change. It is a heartbeat only.

```json
{
  "type": "tick",
  "not_truth": false,
  "source": "transportcell",
  "cell_id": "browser_cell_01",
  "world": "Astro",
  "rev": 123,
  "ts": 1766159000000
}
```

### Truth envelope (WS)
Produced by truth polling and provider commits:

```json
{
  "type": "usd_deltas",
  "cell_id": "browser_cell_01",
  "world": "Astro",
  "rev": 123,
  "ts": 1766159000000,
  "ops": [ /* USD-representable ops */ ],
  "batch": { "index": 0, "count": 2, "max_bytes": 51200 }
}
```

Notes:
- `batch` appears only when ops are chunked (Omniverse-style batching) to stay under a max payload size.
- WS is best-effort. Client must handle gaps by resyncing from `/capabilities` + baseline layers.

### Perception envelope (WS)
Broadcast after successful `POST /perception`:

```json
{
  "type": "perception_ops",
  "not_truth": true,
  "cell_id": "browser_cell_01",
  "world": "Astro",
  "rev": 124,
  "ts": 1766159000000,
  "ops": [ /* same op schema */ ],
  "provenance": { /* supplied by client */ }
}
```

**Invariant**: `not_truth=true` is explicit. UI must never present these as truth.

---

## Op schema (USD‑representable operations)

Each op must have:
- `op` (string)
- `op_id` (string UUID) — required for audit correlation and idempotency
- `path` (USD prim path) when applicable

Common ops used today:
- `UpsertPrim` `{ op, op_id, path, primType }`
- `SetXform` `{ op, op_id, path, translate:[x,y,z], orient:[x,y,z,w], scale:[x,y,z] }`
- `SetAttr` `{ op, op_id, path, name, valueType, value }`
- `RemovePrim` `{ op, op_id, path }`

---

## Revision semantics (“conversation clock”)

`rev` is **monotonic per world**:
- `STATE.rev.bump(world)` increments `current_rev[world]` by 1
- Truth deltas and perception deltas both participate in the same monotonic counter

**Meaning**:
- `rev` is the ordering clock for the world’s USD-representable state stream.
- It is not a blockchain confirmation count; it is a stream revision counter.

**Client reconciliation rule** (implemented as best-effort):
- If a WS delta arrives with a `rev` gap (e.g., last=100 and incoming=105), resync baseline (`GET /capabilities`) and continue.

---

## Append-only perception persistence (audit)

### `POST /perception` (JSON ops)
On success:
- Writes append-only file:
  - `usd/perception/perception_<CELL_ID>_<World>_<rev>_<ts>.json`
- Appends audit entry:
  - `usd/audit/audit.jsonl` event `perception_json`
- Broadcasts WS envelope:
  - `type=perception_ops`, `not_truth=true`

### `POST /usd/perception-layer` (USD overlay bytes)
On success:
- Writes append-only file:
  - `usd/perception/perception_<CELL_ID>_<World>_<rev>_<ts>.usda`
- Appends audit entry:
  - `event=perception_usd`

**Wiring point (source)**:
- `apps/gaiaos_browser_cell/services/usd-transport-cell/main.py`:
  - `post_perception()`
  - `post_perception_layer()`

---

## Truth projection (substrate frames → USD ops → live layer + WS)

When `pxr_ok=true`:
- Transport cell opens the composed stage
- Applies ops to USD
- Saves edit target layer (truth hot layer)
- Broadcasts `usd_deltas`

When `pxr_ok=false`:
- The service runs **degraded-but-honest**
- It can still serve static layers and accept perception, but it must not claim it wrote `live.usdc`

**Truth polling wiring point (source)**:
- `apps/gaiaos_browser_cell/services/usd-transport-cell/main.py` → `truth_poll_loop()`
  - Queries ArangoDB `substrate_frames` and merges `entities`
  - Translates each entity into ops:
    - `UpsertPrim` + `SetXform`
    - dimension attributes:
      - `gaiaos:space`
      - `gaiaos:time`
      - `gaiaos:energy`
      - `gaiaos:consciousness`

This is the literal bridge between “8D substrate-ish” values and USD attributes.

---

## Mapping into UUM‑8D (what the USD stream means to the brain)

UUM‑8D core types live here:
- `uum8d_core/src/lib.rs`

Key structures:
- `Coord8D`:
  - `(x,y,z,t)` + `(psi_virtue, psi_truth, psi_potential, psi_psi)`
- `Uum8dState`:
  - `coord_8d`
  - `entities`
  - `perception` (flags + last_update_ms)
  - `decision_context`

### Proposed canonical mapping (grounded in current USD ops)

#### 1) Truth entities → `UumEntity`
USD prim path:
- `/GaiaOS/Worlds/<World>/<Type>_<substrate_id>`

Maps to:
- `UumEntity.id` = `<Type>_<substrate_id>` (or the full path if you want stable global IDs)
- `UumEntity.position` = `SetXform.translate`
- `UumEntity.velocity` = (not present yet in USD ops; when added, map from `SetAttr gaiaos:vel_*` or similar)
- `UumEntity.entity_type` = `<Type>` mapping

#### 2) “8D voxel dims” currently emitted as USD attrs
Current truth poll emits:
- `gaiaos:space`, `gaiaos:time`, `gaiaos:energy`, `gaiaos:consciousness`

These should map into **UUM‑8D** as:
- `Coord8D.x/y/z/t` (from transform + stage time / frame timestamp)
- `Coord8D.psi_truth` (from FoT coherence computed in UUM‑8D, not from UI)
- `Coord8D.psi_virtue` (from Franklin/virtue engine)
- `Coord8D.psi_potential` (from policy/gnn rollouts)
- `Coord8D.psi_psi` (meta-awareness / self-model signals)

Today, only the raw “voxel” attrs are present; the full psi mapping requires wiring FoT/virtue/policy outputs into USD attrs explicitly (truth) or into perception overlays (hypotheses).

#### 3) Perception ops → `PerceptionState` + append-only evidence
Perception envelopes are explicit `not_truth=true` and should be consumed by UUM‑8D as **inputs**, not as truth:
- Update `PerceptionState.last_update_ms`
- Optionally set `visual_active/audio_active/sensor_active` based on the source
- Add a “pending perception events” queue for downstream validation/promotion decisions

**Critical invariant**:
- Perception can influence UUM‑8D decision-making, but cannot silently overwrite truth.

---

## “Conversation speed” (fast loop expectation)

Right now:
- Truth poll loop requires `pxr_ok=true` to execute the stage write path.
- `current_rev` will only change automatically if:
  - new substrate frames arrive and are applied, or
  - a provider commit occurs, or
  - perception is posted

If you want a visibly “fast” conversation:
- Ensure substrate is producing new frames (Arango `substrate_frames` changing)
- Or drive perception at a high rate (operator marks / sensors)
- Then the UI indicators should move:
  - `Rev (world)` increases
  - `WS Msgs` increases
  - `Last Resync` updates after resync actions

---

## Triage checklist (no UI required)

1) Does `current_rev` change on its own?
- If no, truth/provides aren’t emitting.

2) Does `POST /perception` bump `current_rev[world]`?
- If yes, the append-only perception loop is alive (and should broadcast WS).

3) Do `usd/perception/*` and `usd/audit/audit.jsonl` append?
- If yes, the conversation is being persisted and audited.


