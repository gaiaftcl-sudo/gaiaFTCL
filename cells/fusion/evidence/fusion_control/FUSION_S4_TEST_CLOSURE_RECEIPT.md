# Fusion S⁴ + Discord Tier A — test closure receipt

Regenerated: run the commands below from `cells/fusion/services/gaiaos_ui_web` with **`GAIA_ROOT`** set to the GAIAOS repo root.

## Prerequisites

1. **`fot_mcp_gateway`** (service map **:8803**) reachable at **`MCP_BASE_URL`** (default **`http://127.0.0.1:8803`**): `/health` + `/claims?limit=1`. The gateway forwards **`/mcp/execute`**, **`/evidence/*`**, **`/echo/nonce`** to **gaiaos_ui_tester_mcp** via **`MCP_UI_TESTER_UPSTREAM`** (default **`http://127.0.0.1:8900`** on host; in Docker use **`http://host.docker.internal:8900`** or compose service URL). Tunnel or publish **8803** if testing from a laptop.

2. **Fusion S⁴ UI port** free (default **8910**, or **`FUSION_UI_PORT`**) for Playwright / `dev:fusion` — see **`deploy/mac_cell_mount/MAC_FUSION_MESH_CELL_PORTS.md`**.

3. **Discord Tier B** (storage file):  
   `export DISCORD_PLAYWRIGHT_STORAGE_STATE=/absolute/path/to/discord-state.json`  
   Generate: `npx playwright codegen https://discord.com --save-storage=discord-state.json`

## Commands

| Phase | Command | Artifact / receipt |
|-------|---------|---------------------|
| W1 | `bash scripts/test_fusion_mesh_mooring_stack.sh` | exit 0, PASS counts |
| W5 Tier A | `bash scripts/test_fusion_discord_tier_a.sh` | exit 0; needs MCP up |
| W2 | `npm run test:unit:fusion` | Vitest 13 tests |
| W3–W4 | `GAIA_ROOT=... npm run test:e2e:fusion` | Playwright HTML `playwright-report-fusion/`; screenshot `evidence/fusion_control/playwright/fusion-s4-console.png` |
| W4 doc only | `GAIA_ROOT=... npm run test:e2e:fusion:doc` | same PNG |
| W6 Tier B | `npm run test:e2e:discord` | pass or **skipped** + stderr REFUSED block |
| W7 | `rm -rf .next && GAIA_ROOT=... npm run build` | Next build success |
| W8 | `MCP_BASE_URL=... GAIA_ROOT=... npm run test:fusion:all` | full chain exit 0 |

## Parent plan

After W1–W8 receipts: resume **`cells/fusion/RECURSIVE_BIRTH_PLAN.md`** (next: D-2/D-3 port mesh, C-1 Franklin deploy, B-1 Owl `/moor` deploy witness).

Preflight: **`bash scripts/preflight_mcp_gateway.sh`** (optional `MCP_BASE_URL` if not localhost:8803).

## Slow matrix (optional)

`FUSION_MATRIX_E2E=1 GAIA_ROOT=... npx playwright test --config=playwright.fusion.config.ts tests/fusion/fusion_matrix_e2e.spec.ts`
