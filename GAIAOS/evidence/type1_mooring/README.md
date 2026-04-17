# Type I mooring evidence (append-only)

JSONL files written by [`gaiaos_ui_web`](/GAIAOS/services/gaiaos_ui_web) API routes when operators use **`/moor`**:

| File | Route | Content |
|------|-------|---------|
| `registrations.jsonl` | `POST /api/moor/register` | `wallet_address`, `cell_id` |
| `oaths.jsonl` | `POST /api/moor/oath` | `oath_message_sha256`, optional `signature` |
| `stakes.jsonl` | `POST /api/moor/stake` | `tx_hash`, `chain_id` (verify on-chain separately) |
| `pq_receipts.jsonl` | `POST /api/moor/pq-receipt` | `receipt_sha256`, `closure` (must be `LIGHT_BLUE`) |

Optional: set `MOOR_GATEWAY_INGEST_URL` on the Next server to forward registration payloads to MCP gateway `/ingest` (best-effort; failures do not block local append).

**Download eligibility:** `GET /api/moor/eligibility?walletAddress=&cellId=` (requires all three inception streams). Set server env `TYPE1_PAYLOAD_DOWNLOAD_URL` to surface the DMG/signed URL when unlocked.

**Discord / “Moored Cell”:** `GET /api/moor/status?walletAddress=&cellId=` with optional header `X-Type1-Bot-Secret` when `TYPE1_MOOR_BOT_SECRET` is set. Set `TYPE1_REQUIRE_PQ_FOR_MOORED=1` so `moored_cell` requires a PQ line in `pq_receipts.jsonl`.

Operator runbook: [`../../docs/TYPE1_PUBLIC_PROJECTION_AND_DISCORD.md`](../../docs/TYPE1_PUBLIC_PROJECTION_AND_DISCORD.md).

IQ/OQ/PQ machine receipts: run `type1_iq_oq_pq.py` and store output under `last_type1_receipt.json`. See [`GXP_IQ_OQ_POINTER.md`](./GXP_IQ_OQ_POINTER.md) for TTL wiring.
