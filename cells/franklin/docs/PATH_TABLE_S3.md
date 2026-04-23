# §3 Path table — Mac expert cell (ship review artifact)

**Purpose:** Single table tying **Terminal**, **Lithography**, **Klein**, **Genesys / mesh genesis**, **wellbeing**, and (when shipped) **PoL / INV_LIFE** to **canonical entrypoints**, **evidence**, and **automation**. Reviewer signs at a **pinned** `git` commit (replace `PIN` below).

| Pillar | Canonical entry | Environment | Evidence | Catalog / doc § | Automation check | PoL / INV_LIFE (when shipped) |
|--------|-----------------|-------------|----------|-----------------|------------------|------------------------------|
| **Terminal** | `cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh` | `GAIAFTCL_REPO_ROOT`, `GAIAHEALTH_REPO_ROOT`, `FRANKLIN_GAMP5_SMOKE` | `cells/health/evidence/franklin_mac_admin_gamp5_*.json` | `wiki/Qualification-Catalog.md`; [TERMINAL_DRIVER_CANONICAL.md](TERMINAL_DRIVER_CANONICAL.md) | MacFranklin app; MCP `franklin_run_mac_gamp5`; `zsh` driver from repo root; admin-cell (same script) | — |
| **Lithography** | No single Mac build script: catalog + IQ/OQ docs under `cells/lithography/` | `GAIAFTCL_REPO_ROOT` | `cells/lithography/docs/`, `wiki/Qualification-Catalog.md` §6 | §6 GaiaLithography; [LITHOGRAPHY_MAC_PATH.md](LITHOGRAPHY_MAC_PATH.md) | Full litho GAMP is **not** default on every Mac; Mac cell **proves** alignment by **catalog** + **doc links**; MCP `franklin_lithography_entrypoints` (paths only) | — |
| **Klein** | `zsh cells/franklin/tests/test_mac_mesh_cell_narrative_lock.sh` | `GAIAFTCL_REPO_ROOT` | — | [mesh-topology.md](../../../docs/concepts/mesh-topology.md), [IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md) §9.1 | Script **exit 0**; quarantine = REFUSED in-manifold | — |
| **Mesh genesis** | Operator-declared `mesh_genesis.json` (see [MESH_GENESIS.md](MESH_GENESIS.md)) | `MESH_GENESIS_FILE` or default path in doc | `cells/franklin/evidence/mesh_genesis.json` (recommended) | Plan §2.5 | **SHA** in Genesys must match | — |
| **Per-cell Genesys** | First green GAMP / driver run → emit `cells/health/evidence/genesys_<cell>_<ts>.json` (schema [genesys_record.schema.json](../schema/genesys_record.schema.json)) | same as Terminal + `mesh_genesis_id` / hash | `cells/health/evidence/genesys_*.json` | Plan + [GENESYS_AND_WELLBEING.md](GENESYS_AND_WELLBEING.md) | `franklin_read_text_file` + schema verify (future) | — |
| **Wellbeing** | Rolling Franklin + health GAMP evidence | scheduled smoke / full validate | `franklin_mac_admin_gamp5_*.json`, optional `wellbeing_*.json` | [LIVE_CELL_GAMES.md](LIVE_CELL_GAMES.md) | No red streak past policy | — |
| **PoL / INV_LIFE** | (target) `evidence/pol/<cell>/<tau>/` | PoL spec [INV_LIFE.md](INV_LIFE.md) | `pol_receipt.{bin,json}` | Plan §2.4, Appendix A | `pol_round_trip`, peer witness; **SETTLED** requires valid PoL (Fusion envelope) | **SETTLED** blocked if PoL fails once shipped |

**Ship when:** all **Terminal**, **Lithography**, **Klein** rows have a **non-empty** automation path and a **green** last run at commit **PIN** (e.g. `git rev-parse HEAD`).

**SETTLED vs PoL:** See [INV_LIFE.md](INV_LIFE.md) and plan §3 — until PoL is implemented, envelope **SETTLED** remains gated by **existing** GAMP/OQ only; this table records the **future** hard gate.
