# Live “cell game” smokes (fail-closed, bounded)

**Not all smokes on every run.** The operator chooses cadence; defaults below are **suggested** and must stay **non-interactive** and **bounded** (timeout + exit codes).

| Game | When | Max frequency | On failure | Evidence |
|------|------|---------------|------------|----------|
| **Franklin GAMP5 smoke** | Pre-merge Mac lane, daily dev | 1× per action | **Fail closed:** no merge, fix or REFUSED | `franklin_mac_admin_gamp5_*.json` |
| **Franklin full validate** | Release / weekly / before ship tag | 1–2 hours budget | **Fail closed** | `franklin_gamp5_validate` stdout + exit 0 |
| **Health GAMP5 full** | Cell operator schedule | as policy | **Fail closed** for health sign-off | `health_gamp5_*.json` |
| **Mesh narrative lock** | Any Franklin/IMPLEMENTATION_PLAN/mesh doc change | per PR | **Fail closed** | test exit 0 |
| **Klein mesh tests** (when integrated) | Ring-2/5 per catalog | per release train | Triage: fix or CCR | catalog rows |

**Red streak:** if two consecutive smokes for the same game fail without a CCR, treat lane as **REFUSED** until a green run is recorded in evidence.

**mac_cell_bridge:** connect + one subject (MVP) does not replace GAMP5; it is a **liveness** check only. See [../services/mac_cell_bridge/README.md](../services/mac_cell_bridge/README.md).
