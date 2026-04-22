# Migration — TestRobot → Franklin (scope table)

One word (**TestRobot**) names **three** different scopes. Use the right evidence for each requirement ID.

| Scope | What it is | Authoritative path / note |
|-------|------------|---------------------------|
| **A — Legacy Fusion Metal PQ** | Headless Metal / offscreen **TestRobot** binary (Fusion stack) | Canonical in repo: [`../fusion/macos/TestRobot/`](../fusion/macos/TestRobot/). **Also** a `GAIAOS/macos/TestRobot` tree may exist in some checkouts — treat as the **same scope (A)**: Metal **PQ** harness, **not** full GaiaHealth IQ/OQ. |
| **B — Console “TestRobot (live)”** | GaiaFTCLConsole path that spawns **`admin-cell`** (health orchestrator) | Same **execution plane** as local IQ/OQ/PQ when driven through Console + `admin-cell` (see [`../health/docs/TESTROBOT_VS_HEALTH_IQOQPQ.md`](../health/docs/TESTROBOT_VS_HEALTH_IQOQPQ.md)). |
| **C — Franklin (full GAMP substrate)** | Mac Admin automation + `franklin_mac_admin_gamp5_receipt_v1` | [`../health/scripts/franklin_mac_admin_gamp5_zero_human.sh`](../health/scripts/franklin_mac_admin_gamp5_zero_human.sh), [`../../GAIAOS/mac_cell/FranklinGAMP5Admin/`](../../GAIAOS/mac_cell/FranklinGAMP5Admin/) |

**Rule:** never claim GaiaHealth **GAMP PASS** from scope **A** alone.

**Archive pointer:** [`../../archive/testrobot/README.md`](../../archive/testrobot/README.md)

**Concept layer:** [`../../docs/concepts/franklin-role.md`](../../docs/concepts/franklin-role.md)
