# Narrative to RTM map (living)

**Purpose:** Every major **program narrative** in-repo must map to **product surface (app or service)**, **test or ritual**, and **evidence** — or be flagged **[GAP]**. *Extension* of gaiaFTCL is done only along these rows. *Cursor plan (local):* `.cursor/plans/macfranklin_admin_app_57b74072.plan.md` (if present on your machine).

| Narrative (where stated) | Product / code | Tests / witness | Notes |
|--------------------------|----------------|-----------------|--------|
| Global nine-cell Klein, 5-of-9, REFUSED; Mac: Franklin as admin cell + shared vQbit | [`cells/franklin/IMPLEMENTATION_PLAN.md`](../../cells/franklin/IMPLEMENTATION_PLAN.md), [`docs/concepts/franklin-role.md`](../concepts/franklin-role.md) | `zsh cells/franklin/tests/test_mac_mesh_cell_narrative_lock.sh` | Doc + shell lock (extend to mesh e2e where applicable) |
| GAMP5 IQ/OQ/PQ (Health) | `admin-cell`, `health_full_local_iqoqpq_gamp.sh` | `swift test` in AdminCellRunner; `zsh cells/franklin/scripts/franklin_gamp5_validate.sh` | Evidence: `cells/health/evidence/` |
| Mac Father / Franklin receipts | `franklin_mac_admin_gamp5_zero_human.sh`, `fo-franklin` | Same validate script; `test_franklin_receipt_conformance.sh` | Pins: `cells/franklin/pins.json` — refresh when scripts change |
| **MacFranklin** operator UI | `cells/health/swift/MacFranklin` → `.app` | `zsh cells/franklin/scripts/franklin_mac_full_package_validate.sh` (GAMP5 + fo_cell_substrate + app); or `zsh cells/health/swift/MacFranklin/build_macfranklin_app.sh`; manual smoke in Finder | Same driver as CLI — no second automation |
| **GaiaFusion (operator surface)** — **Swift** | [`cells/fusion/macos/GaiaFusion/`](../../cells/fusion/macos/GaiaFusion) — SwiftUI, `FusionBridge`, WKWebView loads **embedded** `Resources/fusion-web/`, **WASM** `gaiafusion_substrate.wasm` + constitutional checks | `xcodebuild` / [`cells/fusion/scripts/`](../../cells/fusion/scripts); `Tests/` e.g. `UIValidationProtocols` (WASM in bundle) | The product UI is the **.app**; embedded web chunks are **bundled assets**, not a separate “we run Next as the app.” |
| [GAP] `cells/fusion/services/gaiaos_ui_web` | Optional **source** to **export** static assets into GaiaFusion bundle — **not** the shipped operator app by itself | Only if the team still builds that pipeline; not required to describe Mac cell truth | If unused, delete or archive; do not treat as primary UI. |
| `fo-fusion` / `fo-health` / `fo-franklin` gates | `cells/shared/rust/fo_cell_substrate`, `cargo build` at workspace root | Shell tests in `cells/fusion/scripts`, `cells/franklin/tests` | |

**Maintainers:** when you add a user-facing **story** in `wiki/` or `docs/`, add a **row** here or link the wiki page to an existing ID.

**Open items** still tracked in [`OPEN_LOOPS.md`](OPEN_LOOPS.md) until closed.
