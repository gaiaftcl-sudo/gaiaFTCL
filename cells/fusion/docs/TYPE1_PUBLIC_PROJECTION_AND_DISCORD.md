# Type I mooring — public projection and Discord

**Audience:** Operators wiring **Type I mooring** (inception streams, eligibility, Discord “Moored Cell” status).

**Canonical evidence folder:** [`../evidence/type1_mooring/`](../evidence/type1_mooring/)

## API surface (summary)

- **Download eligibility:** `GET /api/moor/eligibility?walletAddress=&cellId=` (requires all three inception streams). Configure server env `TYPE1_PAYLOAD_DOWNLOAD_URL` when the DMG/signed URL should surface after unlock.
- **Discord / “Moored Cell”:** `GET /api/moor/status?walletAddress=&cellId=` with optional header `X-Type1-Bot-Secret` when `TYPE1_MOOR_BOT_SECRET` is set. Use `TYPE1_REQUIRE_PQ_FOR_MOORED=1` so `moored_cell` requires a PQ line in `pq_receipts.jsonl`.

## IQ/OQ/PQ machine receipts

Run `cells/fusion/infrastructure/vqbit_cursor_kit/scripts/type1_iq_oq_pq.py` and store output under `cells/fusion/evidence/type1_mooring/last_type1_receipt.json`. Schema: `cells/fusion/infrastructure/vqbit_cursor_kit/schemas/type1_receipt.v1.json`. TTL wiring: [`../evidence/type1_mooring/GXP_IQ_OQ_POINTER.md`](../evidence/type1_mooring/GXP_IQ_OQ_POINTER.md).

---

*Norwich / GaiaFTCL — mooring receipts are append-only.*
