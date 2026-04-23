# vQbit Expert ABI (design note)

**Position:** The Mac / Franklin expert surface extends **`fo_cell_substrate`** and existing **GAMP5 receipt** shapes; it does **not** introduce parallel “expert-only” ledgers for the same physical facts.

**Principles**

1. **One substrate:** Batches, `CellReceipt`, and migration hooks stay in `cells/shared/rust/fo_cell_substrate` (or canonical Rust paths per repo). Expert logic adds **envelope** fields or new **receipt kinds** only through a **versioned** extension document and schema bump.

2. **No duplicate types:** “Expert” outcomes that are really the same as a standard **PASS / REFUSED / FATAL** must use those lanes; new enums only for **genuinely** new semantic classes (e.g. PoL-specific when shipped).

3. **Append-only and audit:** vQbit/calorie semantics: extend **forward**; do not fork historical schemas for convenience.

4. **Bridge (MVP):** `mac_cell_bridge` is **NATS liveness** only, not a second receipt store; evidence remains JSON under `cells/health/evidence/` and Arango/Graph paths per product cells.

5. **Future PoL:** `pol_receipt` links into the same **audit** story; round-trip and witness fields attach to the envelope spec in plan Appendix A.

**Action for implementers:** Before adding a new JSON type under `cells/franklin/`, check **Qualification-Catalog** and `fo_cell_substrate` and prefer **extending** one family.
