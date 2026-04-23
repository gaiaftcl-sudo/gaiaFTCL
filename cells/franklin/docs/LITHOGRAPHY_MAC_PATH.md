# Lithography — Mac cell alignment (read-only on typical dev Mac)

The **M8 / lithography** product cell is first-class in [`wiki/Qualification-Catalog.md`](../../../wiki/Qualification-Catalog.md) (§6 — GaiaLithography event classes, NATS, GAMP5 lifecycle cross-links).

A **Mac development** node does not always run full litho IQ/OQ locally. The Mac cell still stays **closed** w.r.t. the substrate if:

1. The operator **acknowledges** lithography rows in the Qualification-Catalog and **links** here from the §3 path table.
2. **MCP** exposes **pointers** only: see tool `franklin_lithography_entrypoints` (paths under `GAIAFTCL_REPO_ROOT`).

**Authoritative code/docs:** `cells/lithography/docs/`, `cells/lithography/wiki/`, `wiki/M8_Lithography_Silicon_Cell_Wiki.md` (if mirrored).

**If** a full litho validate script is added on `main`, add a **new row** to `PATH_TABLE_S3.md` — do not silently claim coverage without a green automation check.
