# Mesh Genesis — file, SHA, and Genesys link

**Bootstrap story:** Every physical mesh (tokamak / rack / lab) is declared by an operator with a **mesh_genesis** record: *who* turned the key, *when*, *where*, and a **config SHA** of the “first green” state.

| Field | Source |
|-------|--------|
| **file** | Default: `cells/franklin/evidence/mesh_genesis.json` (or `MESH_GENESIS_FILE` env) |
| **hash** | SHA-256 of canonical JSON (or committed bytes per policy) **must** match the field in per-cell [Genesys](../schemas/genesys_record.schema.json) `mesh_genesis_hash` when Genesys is emitted |
| **id** | Stable string `mesh_genesis_id` in Genesys links back to the same file |

**Why:** Prevents a cell from “claiming” a mesh without a recorded genesis; ties **MANDATORY** racking to operator authority.

**If missing:** GAMP5 may still run on a **dev** Mac without the file, but **ship** and **infrastructure** sign-off should require a committed genesis + green evidence path.

See [PATH_TABLE_S3.md](PATH_TABLE_S3.md) and [GENESYS_AND_WELLBEING.md](GENESYS_AND_WELLBEING.md).
