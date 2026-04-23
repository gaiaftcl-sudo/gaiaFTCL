# Normative vs interpretive; invariant → evidence × script

**Normative (P0, ship / merge blockers on Mac):**

- One canonical `franklin_mac_admin_gamp5` driver: `franklin_mac_admin_gamp5_zero_human.sh` (no duplicate “shadow” driver).
- Swift tests + GAMP5 validate: `zsh cells/franklin/scripts/franklin_gamp5_validate.sh` (before merge when touching that lane per repo policy).
- `franklin_mac_admin_gamp5_*.json` in `cells/health/evidence/`; catalog alignment `wiki/Qualification-Catalog.md` + **mesh narrative lock** green.
- Klein lock: `test_mac_mesh_cell_narrative_lock.sh` exit 0 when narrative changes.

**Interpretive (non-blocking until stated otherwise):** PoL round-trip in hardware, 15s full hash, 1 ms torsion, M8 litho on every dev Mac, full Genesys automation — see [ROADMAP_PHYSICS.md](ROADMAP_PHYSICS.md).

| Invariant | Evidence (what to point at) | Script / check |
|-----------|-----------------------------|-----------------|
| Single driver, same env | `franklin_mac_admin_gamp5_*.json` + script path in receipt | `franklin_run_mac_gamp5` / `franklin_mac_admin_gamp5_zero_human.sh` |
| Swift + GAMP5 validate | validate stdout, exit 0 | `franklin_gamp5_validate` |
| Health catalog / Ring-0 | `fo_health --gaiaos-version-gamp5` (when built) | `fo_health_gamp5_catalog` (MCP) |
| Health cell GAMP5 (full) | `cells/health/evidence/health_gamp5_*.json` | `health_cell_gamp5_validate` (long) |
| Klein + Franklin narrative | (none extra if lock only) | `franklin_mesh_narrative_lock` |
| Mesh Genesis SHA | `mesh_genesis.json` + `genesys_*.json` if emitted | [MESH_GENESIS.md](MESH_GENESIS.md), schema |

**Tag:** In ship PRs, label interpretive work **[I]** in text when it is not yet merge-gating on `main`.
