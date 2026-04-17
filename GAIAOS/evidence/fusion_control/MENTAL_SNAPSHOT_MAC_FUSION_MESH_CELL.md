# Mental snapshot — Mac Fusion as mesh leaf cell (return here)

**Date:** 2026-04-03 (updated 2026-04-04 — sovereign sidecar + active plan)  
**Context:** Mesh firewalls closed; Mac Fusion stack is **not** a parallel universe—it is a **leaf cell** with the same mooring contract as fleet cells (wallet, mount, Discord membrane, gateway, NATS heartbeat).

---

## Return stack (read in this order)

1. **This file** — port invariants + sidecar one-liners.  
2. **`evidence/fusion_control/FUSION_SIDECAR_ACTIVE_PLAN.md`** — new **FusionSidecarHost** target + Fusion **deploy packaging**, **zero repo blockers** proof, **deployment runbook** (cell Mac).  
3. **`GAIAOS/RECURSIVE_BIRTH_PLAN.md`** — **parent** birth roadmap (Franklin, nine-cell mesh, DMG sovereignty, etc.).

---

## Sovereign sidecar (closed in-app VM host)

- **Xcode app:** `macos/FusionSidecarHost/` — **Virtualization.framework** Linux VM + **TCP bridge** host `127.0.0.1:8803` → guest gateway (default guest IP `192.168.64.10`, configurable). Optional **read-only virtiofs** of GAIAOS root, tag **`gaiaos`** (UI: *GAIAOS tree*).
- **Guest bootstrap:** `deploy/mac_cell_mount/fusion_sidecar_guest/` — cloud-init fragment, static net, `mount-gaiaos-virtiofs.sh`, `fusion-sidecar-compose.service`.
- **Guest C⁴ stack:** `docker-compose.fusion-sidecar.yml` (`fusion-sidecar-gateway` + `fusion-sidecar-tester`, `MCP_UI_TESTER_UPSTREAM=http://fusion-sidecar-tester:8900`).
- **Operator / guest image docs:** `deploy/mac_cell_mount/FUSION_SIDECAR_HOST_APP.md`, `FUSION_SIDECAR_GUEST_IMAGE.md`.
- **Distribution:** **No App Store** — build locally with Xcode; cells get **`FusionSidecarHost.app`** by zip/rsync/download (see **FUSION_SIDECAR_HOST_APP.md** §5).
- **Repo limb receipt:** `VERIFY_FUSION_SIDECAR_XCODE=1 bash scripts/verify_fusion_sidecar_bundle.sh` → **CALORIE**; Vitest fusion **13/13** (`npm run test:unit:fusion` in `services/gaiaos_ui_web`).

---

## Port invariants (no drift)

| Layer | Port(s) | Role |
|-------|---------|------|
| **C⁴** | **8803** | Only MCP **ingress** (`fot_mcp_gateway` / wallet-gate path). UI/API proxies target this; tunnel to head, **FusionSidecarHost** bridge, or local gateway stack. |
| **C⁴** | **4222** | NATS on the wire (internal to stack). Mac reaches via **SSH tunnel**: local **`127.0.0.1:14222` → head `4222`** (`bin/nats_tunnel_head.sh`). **14222** = local bind, not a new mesh wire port. |
| **C⁴** | **8900** | `gaiaos_ui_tester_mcp` upstream for gateway (`MCP_UI_TESTER_UPSTREAM`) when co-located on host. |
| **S⁴** | **8910** (default) | Loopback Fusion Next UI (`/fusion-s4`). Override only with **`FUSION_UI_PORT`** if port collision. |
| **Plant** | Site-defined | Real/virtual tokamak / MARTe2 / TORAX I/O from **`fusion_projection.json`**, **`deploy/fusion_cell/config.json`**, facility runbooks—not arbitrary dev ports. |

**Canonical doc:** `deploy/mac_cell_mount/MAC_FUSION_MESH_CELL_PORTS.md`  
**Mooring PUB + vQbit matrix (terminal states):** `deploy/mac_cell_mount/MAC_CELL_MOORING_AND_VQBIT.md`, `deploy/mac_cell_mount/launchd/README.md`  
**Fleet health witness:** `scripts/witness_mac_cell_fleet_health.sh` → `evidence/fusion_control/mac_cell_fleet_health_witness.json`  
**GaiaFusion “green” spine:** `scripts/run_gaiafusion_release_smoke.sh` → `evidence/fusion_control/gaiafusion_release_smoke_receipt.json` (see `macos/GaiaFusion/README.md`)  
**Code constants:** `services/gaiaos_ui_web/app/lib/macFusionCellPorts.ts` (`C4_*`, `S4_*`, `fusionUiPort()`).

---

## Key wiring (what we aligned)

- **`substrateMcpUrl.ts`**, **`mcp-client.ts`**, **`sovereign-gateway.ts`**, **`playwright.config.ts`**, **`tests/helpers/mcp-helper.ts`** → fallback MCP base uses **`C4_MCP_INGRESS_PORT`** (8803), not scattered literals.
- **`package.json` `dev:fusion`** → `sh -c` with **`FUSION_UI_PORT`** (default 8910) so **`scripts/fusion_stack_launch.sh`** and Playwright stay consistent.
- **`playwright.fusion.config.ts`** → **`fusionUiPort()`** for `baseURL` / `webServer` URL.
- **`docker-compose.cell.yml`** → `fot-mcp-gateway-mesh` has **`MCP_UI_TESTER_UPSTREAM`** (default `host.docker.internal:8900` for Docker Desktop; Linux overrides env).
- **`scripts/validate_ui.sh`** → tester **8900**, gateway **8803**, Playwright **`MCP_BASE_URL`** → 8803.
- **Narrative:** `FUSION_DM_VIRTUAL_AND_PRODUCTION.md`, `README_MEMBRANE.md`, `FUSION_S4_TEST_CLOSURE_RECEIPT.md` point at the port invariant doc.

---

## When you resume

1. **`MENTAL_SNAPSHOT_MAC_FUSION_MESH_CELL.md`** (this file).  
2. **`FUSION_SIDECAR_ACTIVE_PLAN.md`** — sidecar packaging + deploy runbook + verify receipts.  
3. **`MAC_FUSION_MESH_CELL_PORTS.md`** before adding any new listener.  
4. **`macFusionCellPorts.ts`** for TS port constants.  
5. **`RECURSIVE_BIRTH_PLAN.md`** — parent mesh / Franklin / DMG thread.  
6. **Bundle verify:** `VERIFY_FUSION_SIDECAR_XCODE=1 bash scripts/verify_fusion_sidecar_bundle.sh`.

*Norwich / GaiaFTCL — S⁴ serves C⁴.*
