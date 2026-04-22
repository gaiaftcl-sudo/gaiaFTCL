# Franklin Mac Admin — GAMP5 zero-human cell

This is the **Mac Admin self-healing cell** package: one script drives **admin-cell** (GAMP5 IQ/OQ/PQ substrate), optionally **GaiaFTCLConsole** `verify_build_and_test.sh`, and writes a **Franklin receipt** under `cells/health/evidence/`.

- **Role:** same “head living game / mesh” framing as the GAIAOS operator loop: the **cell** runs its own qualification without IDE paste; receipt JSON is the witness.
- **Canonical script:** `cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh` (FoT8D repo root).
- **Wrapper (this folder):** `run_franklin_mac_admin_gamp5.sh` resolves the FoT8D root from `GAIAOS/mac_cell/FranklinGAMP5Admin` and execs the canonical script.

## Run (manual or LaunchAgent)

```bash
# From repo: fast smoke (default)
zsh cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh

# Or from GAIAOS:
zsh mac_cell/FranklinGAMP5Admin/run_franklin_mac_admin_gamp5.sh
```

**MacFranklin (GUI):** build the `.app` (same `franklin_mac_admin_gamp5_zero_human.sh` as CLI) — [`cells/health/swift/MacFranklin/README.md`](../../../cells/health/swift/MacFranklin/README.md). **Zero drift:** no second automation path. The app **auto-binds** the repo via `GAIAFTCL_REPO_ROOT` / `GAIAHEALTH_REPO_ROOT` or by walking from the bundle / cwd; use **Override repository…** only if needed, then **Run GAMP5 smoke** or full chain.

Environment:

| Variable | Meaning |
|----------|---------|
| `FRANKLIN_GAMP5_SMOKE=1` | Self-test + orchestrator `--dry-run` (+ optional Console verify). **Default.** |
| `FRANKLIN_GAMP5_SMOKE=0` | Run full unattended orchestrator (`--dev-mode --skip-ui` + deviation); long. |
| `FRANKLIN_INCLUDE_CONSOLE_VERIFY=1` | Run `GAIAOS/macos/GaiaFTCLConsole/scripts/verify_build_and_test.sh` if present. |
| `FRANKLIN_INCLUDE_FOT8D_RING2=1` | After health chain, run repo `gamp5_iq/oq/pq` (see orchestrator). |

**Launchd:** copy `com.fortressai.franklin.mac.admin.gamp5.example.plist`, set `ABSOLUTE_PATH_TO_FOT8D`, then `launchctl load`.

Evidence: `cells/health/evidence/franklin_mac_admin_gamp5_*.json`.
