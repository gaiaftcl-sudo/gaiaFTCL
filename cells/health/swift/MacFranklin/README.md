# MacFranklin

macOS **app bundle** for the same **admin-cell / Franklin** GAMP5 driver as the CLI. It runs [`cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh`](../../scripts/franklin_mac_admin_gamp5_zero_human.sh).

**Boot behavior (fail-closed LIFE game):** on app start, MacFranklin now runs a required chain and only reports **ALIVE** when all pass:
1) `cells/franklin/tests/test_mac_mesh_cell_narrative_lock.sh`  
2) `cells/health/scripts/health_cell_gamp5_validate.sh --skip-cargo-test`  
3) `cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh` with `FRANKLIN_GAMP5_SMOKE=1`  
Any non-zero exit is **REFUSED** (not alive).

**No-setup live cell (default):** on launch, the app tries **`GAIAFTCL_REPO_ROOT`**, then **`GAIAHEALTH_REPO_ROOT`**, then walks the filesystem **up** from the `.app` bundle and from the process **current directory** until it finds `cells/health/scripts/health_full_local_iqoqpq_gamp.sh` (same tree as a normal FoT8D / gaiaFTCL clone). You should not need a manual repo pick when the app lives inside a checkout or is opened from a shell whose cwd is the repo. Use **Override repository…** only when auto-locate is wrong.

**OpenUSD:** `Sources/Resources/FranklinLiveCell.usda` is bundled; the 3D view is a SceneKit “live” preview (Plasma + Puck orbit) you can **orbit/inspect**; the ASCII is shown in the side panel. Full USD/Hydra remains in the Fusion / GaiaFusion stack.

## Build the `.app`

```bash
zsh cells/health/swift/MacFranklin/build_macfranklin_app.sh
open cells/health/swift/MacFranklin/.build/MacFranklin.app
```

**Guaranteed terminal output + `open` in one step** (add-on; not part of the abstract “expert cell” doc pack): `zsh cells/health/swift/MacFranklin/open_macfranklin_app.sh` — see [ADDON_APP_VISIBLE_PROOF.md](ADDON_APP_VISIBLE_PROOF.md).

**Full pre-push pack** (GAMP5 validate + `fo_cell_substrate` release + this `.app`): from repo root run `zsh cells/franklin/scripts/franklin_mac_full_package_validate.sh` (see [cells/franklin/README.md](../../../franklin/README.md)).

## Zero drift (lock)

| Must stay one path | This app |
|--------------------|----------|
| GAMP5 driver | Only [`franklin_mac_admin_gamp5_zero_human.sh`](../../scripts/franklin_mac_admin_gamp5_zero_human.sh) (via `RunEnvironment` + same env keys as `admin-cell` CLI) |
| Pins | [`cells/franklin/pins.json`](../../../franklin/pins.json) + [`cells/health/.admincell-expected/orchestrator.sha256`](../../.admincell-expected/orchestrator.sha256) — refresh with `zsh cells/franklin/scripts/refresh_franklin_pins.sh` when scripts change |
| Proof | `zsh cells/franklin/scripts/franklin_gamp5_validate.sh` (must be green before merge) |
| GAIAOS wrapper | [`GAIAOS/mac_cell/FranklinGAMP5Admin/`](../../../../GAIAOS/mac_cell/FranklinGAMP5Admin/) `run_franklin_mac_admin_gamp5.sh` still `exec`’s the same canonical script — no duplicate logic |

## Develop (SwiftPM)

```bash
cd cells/health/swift/MacFranklin
swift build
swift run MacFranklin
```

Depends on [`AdminCellRunner`](../AdminCellRunner/) (library product `AdminCellCore`).

## Operator notes

- **GAMP5 smoke** = default in the script (`FRANKLIN_GAMP5_SMOKE=1` in driver for smoke path).
- **Full GAMP5** = long unattended run (`FRANKLIN_GAMP5_SMOKE=0`); use when you intend a full local qualification.
- Evidence: `cells/health/evidence/franklin_mac_admin_gamp5_*.json` under the selected repo.
- **Cursor / MCP:** a Rust **stdio** MCP server is used: `cargo build -p macfranklin_mcp_server --release`, then configure Cursor to run `target/release/macfranklin_mcp_server` (use in-app **Copy Cursor MCP config JSON**). Full wiring and ports vs mesh HTTP `:8803` is documented in [`mcp/MCP_CURSOR.md`](mcp/MCP_CURSOR.md).
- This app does not replace `admin-cell` or the shell pins — it is a **convenience shell** for the same entry points as [`GAIAOS/mac_cell/FranklinGAMP5Admin/`](../../../../GAIAOS/mac_cell/FranklinGAMP5Admin/).
