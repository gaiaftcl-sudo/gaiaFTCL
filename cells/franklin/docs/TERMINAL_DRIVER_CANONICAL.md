# Terminal driver — one canonical path (no duplicate logic)

**Invariant:** every Mac-lane automation that runs Franklin GAMP5 in “admin / zero-touch” mode must **exec the same** shell driver:

- **`cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh`**

**Allowed call surfaces (all equivalent entry points, same script):**

| Surface | How it runs the driver | Env (minimum) |
|---------|------------------------|---------------|
| **MacFranklin.app** | `Process` + `/bin/sh` + `driverPath` | `GAIAFTCL_REPO_ROOT`, `GAIAHEALTH_REPO_ROOT`, `FRANKLIN_GAMP5_SMOKE` |
| **stdio MCP** | `macfranklin_mcp_server.py` → `_run_shell` → `DRIVER` | same + `GAIAFTCL_REPO_ROOT` |
| **GAIAOS** `mac_cell/FranklinGAMP5Admin/` | `run_franklin_mac_admin_gamp5.sh` must **`exec`** the canonical path (per wrapper README) | same |
| **admin-cell** CLI | Same script path under selected repo | `RunEnvironment` + same keys as Swift |
| **Manual** | `zsh` or `sh` from repo root | same |

**Forbidden:** copy-pasting driver logic into a second `.sh` that “mostly” matches; a second `franklin_mac_*` driver for the same role without CCR. Evidence family must stay `franklin_mac_admin_gamp5_*.json` under `cells/health/evidence/`.

**Qualification-Catalog** mapping: GAMP5 receipt family `franklin_mac_admin_gamp5_receipt_v1` (see script header).
