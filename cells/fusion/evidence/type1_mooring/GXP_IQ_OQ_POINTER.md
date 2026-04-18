# GxP IQ / OQ evidence pointer (TTL alignment)

Manufacturing-style **Installation Qualification (IQ)** and **Operational Qualification (OQ)** machine receipts for the Type I pipeline are produced by:

- `cells/fusion/infrastructure/vqbit_cursor_kit/scripts/type1_iq_oq_pq.py`
- Output schema: `cells/fusion/infrastructure/vqbit_cursor_kit/schemas/type1_receipt.v1.json`
- Latest local witness (when run): `cells/fusion/evidence/type1_mooring/last_type1_receipt.json`

**Performance Qualification (PQ)** is represented in the same receipt under the `pq` object (`vq_check` + optional authenticated `/moor/ping`).

Rust TTL placeholders (`gxp_iq`, `gxp_oq` in `TTL_RUST_IMPLEMENTATION_MAP.md`) can assert file presence or HTTP fetch of these artifacts when wiring automated compliance checks.
