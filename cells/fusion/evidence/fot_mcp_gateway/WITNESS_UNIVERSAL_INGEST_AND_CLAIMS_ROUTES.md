# Witness — gateway routes: `universal_ingest` wire-up + `GET /claims`

**generated_utc:** 2026-03-25 (session)  
**scope:** `services/fot_mcp_gateway/main.py`, `universal_ingest.py`, `Dockerfile`, `deploy.sh`

## What was added (no removal of existing routes)

### 1. `POST /universal_ingest`

- **Import:** `from universal_ingest import universal_ingest`
- **Handler:** Passes the JSON body to `await universal_ingest(request)` and returns its dict.
- **Purpose:** Exposes the module’s typed-claim flow (`type` / `payload` / `from`): writes a document shaped by `universal_ingest` into `mcp_claims`, runs classification stubs (`franklin_reflect`, `route_to_game`, `franklin_classify_and_route`), and may write `game_closure_events` / `philosophical_reflections` per that module’s logic.
- **Relationship to `POST /ingest`:** **Unchanged.** `/ingest` remains the constitutional door (`caller_id` / `wallet_address` + substance check, NATS `gaiaftcl.claim.created`). `/universal_ingest` is a **parallel** entry point with **different** validation and document shape.

### 2. `GET /claims`

- **Query parameters:**
  - `limit` — default **20**, range 1–1000
  - `filter` — optional string; case-insensitive substring match via `CONTAINS(LOWER(TO_STRING(c.payload)), LOWER(@payload_match))`. Empty/absent = no payload filter.
- **AQL:** `FOR c IN mcp_claims` → optional payload filter → **`SORT c.created_at DESC`** → **`LIMIT @lim`** → **`RETURN c`** (full documents, same recency basis as `query_full_substrate` → `recent_claims`).
- **Response:** JSON array of raw claim documents (Arango cursor `result`).

## Packaging / deploy

- **`Dockerfile`:** `universal_ingest.py` copied into the image next to `main.py` so `import universal_ingest` resolves at runtime.
- **`deploy.sh`:** `universal_ingest.py` included in `scp` to the cell build context.

## Not done (per instructions)

- No Mailcow changes.
- No inbound mail adapter.

## Verification (operator)

After deploy:

```bash
curl -sS "http://<gateway>:8803/health"
curl -sS "http://<gateway>:8803/claims?limit=5"
curl -sS "http://<gateway>:8803/claims?limit=10&filter=KNOWLEDGE"
```

**Calories or cures. Foundation first.**
