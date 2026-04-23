# Genesys (per cell) and wellbeing (racking / schedule)

**Genesys** (first **green** GAMP5 / driver for a **named cell**):  
Emit one JSON per milestone under `cells/health/evidence/`, name pattern `genesys_<cell>_<ts>.json`, against schema [genesys_record.schema.json](../schemas/genesys_record.schema.json). Include `mesh_genesis_id` and `mesh_genesis_hash` when mesh genesis is in use.

**Wellbeing (operator series):** Not a new physics; it is **scheduled** re-validation that the racking and Mac lane still match catalog + MANDATORY rules. Suggested: rolling `franklin_gamp5_validate` and health GAMP5 on a **calendar**; store pointers in evidence and link from [LIVE_CELL_GAMES.md](LIVE_CELL_GAMES.md).

**Optional MCP read:** `franklin_list_evidence` / `franklin_read_text_file` for `genesys_*.json` and `franklin_mac_admin_gamp5_*.json` (already in server).

**Racking (M8):** Physical placement is out-of-band in JSON here; the **wiring** to catalog is in `wiki/Qualification-Catalog.md` and [LITHOGRAPHY_MAC_PATH.md](LITHOGRAPHY_MAC_PATH.md).

**Wellbeing rack (operational, not a second physics):** After Genesys, treat **wellbeing** as a **rolling** series of the same GAMP5 games. Operator-facing queries (MCP: `franklin_wellbeing_status`) are **read-only** summaries: **last good** timestamp from the newest `franklin_mac_admin_gamp5_*.json` and **genesys_*.json** (if any), and whether there is a **red streak** (two or more **failed** scheduled games without a CURE receipt — must be triaged in your runbook; the agent does not infer “healthy” from vibes). Compare [LIVE_CELL_GAMES.md](LIVE_CELL_GAMES.md) for cadence and fail-closed policy.
