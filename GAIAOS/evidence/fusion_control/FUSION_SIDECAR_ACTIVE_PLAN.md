# Fusion sovereign sidecar — **active plan** (repo limb)

**What this is:** **New Xcode target** (`FusionSidecarHost`) + **Fusion stack deployment packaging** — guest **`docker-compose.fusion-sidecar.yml`**, **8803** bridge, bootstrap files. It does **not** re-prove physics stacks you already run on a laptop (e.g. TORAX path); it wires **MCP ingress** and **cell-consistent ports** for Fusion on Mac cells.

**Scope:** Mac **closed sidecar + guest MCP cell** only. It does **not** subsume **`RECURSIVE_BIRTH_PLAN.md`** (Franklin C-1, nine-cell NATS, full DMG sovereignty narrative, etc.).

---

## Parent birth snapshot — where to return

| Order | Read first | Role |
|-------|------------|------|
| 1 | **`evidence/fusion_control/MENTAL_SNAPSHOT_MAC_FUSION_MESH_CELL.md`** | Mac leaf cell, port invariants, sidecar summary, resume bullets |
| 2 | **`evidence/fusion_control/FUSION_SIDECAR_ACTIVE_PLAN.md`** (this file) | Sidecar execution + zero-repo-blocker proof |
| 3 | **`GAIAOS/RECURSIVE_BIRTH_PLAN.md`** | Full mesh / Franklin / DMG narrative (separate epic) |

**Understanding:** The **mental snapshot** is the **door** back into Mac Fusion + mesh port discipline. The **birth plan** is the **parent** roadmap for the whole substrate; the sidecar is one **limb** that must not invent ports and must keep **8803** as MCP ingress for this path.

---

## Zero blockers — **repository & build limb** (this effort)

Meaning: **nothing in git prevents** building, validating, and shipping the sidecar artifacts. **Deploying** on a cell Mac (copy `.app`, first open if Gatekeeper asks, point at kernel/disk, run compose in guest) is the same class of work as any **internal Mac tool** — documented in **`FUSION_SIDECAR_HOST_APP.md`**, not a separate “approval” loop from the limb.

| Check | Receipt |
|-------|---------|
| Compose valid | `docker compose -f docker-compose.fusion-sidecar.yml config` → exit **0** |
| Guest shell sane | `bash -n deploy/mac_cell_mount/fusion_sidecar_guest/mount-gaiaos-virtiofs.sh` → exit **0** |
| Xcode app builds | `VERIFY_FUSION_SIDECAR_XCODE=1 bash scripts/verify_fusion_sidecar_bundle.sh` → **CALORIE** |
| No `BLOCKED` / `FIXME` in sidecar tree | `macos/FusionSidecarHost/**`, `deploy/mac_cell_mount/*SIDECAR*`, `deploy/mac_cell_mount/fusion_sidecar_guest/**` — **none** (limb audit) |
| Fusion unit gates (S⁴ projection codepath) | `cd services/gaiaos_ui_web && npm run test:unit:fusion` → **13/13** |

**Single command (bundle):**

```bash
cd GAIAOS && VERIFY_FUSION_SIDECAR_XCODE=1 bash scripts/verify_fusion_sidecar_bundle.sh
```

---

## Deployment runbook (cell Mac — one page)

Same steps whether the `.app` arrives by **zip/rsync** or **DMG**; details in **`deploy/mac_cell_mount/FUSION_SIDECAR_HOST_APP.md`**.

1. Place **`FusionSidecarHost.app`** where operators run it (e.g. `/Applications`).
2. If Gatekeeper complains on first launch: **Right-click → Open** (standard for self-distributed builds).
3. Select kernel, initrd, root `.raw`; optional **GAIAOS** folder for virtiofs **`gaiaos`**.
4. **Start VM** → guest: virtiofs mount if needed → **`docker compose -f docker-compose.fusion-sidecar.yml up -d --build`**.
5. **Start bridge :8803** → host: **`curl -sS http://127.0.0.1:8803/health`**.

---

## Parallel limbs (still valid)

See **`evidence/fusion_control/FUSION_SIDECAR_FIELD_OF_FIELDS.md`** — L1–L4 can run on different machines; runtime chain is serial.

---

## After sidecar is green — parent plan

Resume **`RECURSIVE_BIRTH_PLAN.md`** from your current branch (e.g. **C-1 Franklin**, **D-2/D-3** mesh) — orthogonal to this limb unless you explicitly tie MCP ingest to deployed gateway on cells.

---

*Norwich / GaiaFTCL — S⁴ serves C⁴.*
