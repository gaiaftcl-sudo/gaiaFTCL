# Klein closure — operational (mesh narrative lock)

**Definition (repo):** The global nine-cell graph uses a **Klein-bottle** metaphor: no privileged exit; quarantine stays **in-manifold** (REFUSED-class, not an off-ramp). See [`docs/concepts/mesh-topology.md`](../../../docs/concepts/mesh-topology.md).

**Enforcement on `main`:** `zsh cells/franklin/tests/test_mac_mesh_cell_narrative_lock.sh` must **exit 0** before a merge that changes Franklin / Mac cell narrative. It locks doc titles and rows against drift from [`IMPLEMENTATION_PLAN.md`](../IMPLEMENTATION_PLAN.md) (Klein / Father / vQbit sections).

**MacFranklin** must not assert mesh topology that contradicts that lock; if the test fails, **REFUSED** the doc change, fix prose, re-run.
