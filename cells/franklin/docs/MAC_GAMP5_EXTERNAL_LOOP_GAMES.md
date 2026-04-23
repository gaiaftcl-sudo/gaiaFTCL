# Mac GAMP5 External Loop — catalog game mapping and owner signoff

This document defines the outside-in loop for owner-Mac signoff using real games, real captures, and append-only receipts.

## Command flow

1. `zsh cells/franklin/scripts/mac_gamp5_external_loop.sh`
2. Mandatory observer games:
  - `franklin_capture_screenshot`
  - `franklin_runtime_state_latest`
  - `franklin_visual_validate`
  - `franklin_publish_game_receipt`
3. Rust external observer (non-Python path in orchestrator):
  - `cargo build -p mac_gamp5_observer --release`
  - `target/release/mac_gamp5_observer` (invoked by `mac_gamp5_external_loop.sh`)
4. Build owner pack:
  - `zsh cells/franklin/scripts/mac_gamp5_signoff_pack.sh`

## Runtime game states (app self-addressable)

- `BOOTSTRAP`
- `READY`
- `RUNNING_GAMES`
- `REFUSED`
- `CURE`
- `ALIVE`

State snapshots are written to `cells/health/evidence/macfranklin_state/state_*.json` with schema `macfranklin_runtime_state_v1`.

## Qualification-Catalog mapping


| External-loop game              | Primary script/tool                                                                      | Evidence output                                                   | Catalog anchor                                     |
| ------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------- |
| Klein narrative closure         | `cells/franklin/tests/test_mac_mesh_cell_narrative_lock.sh`                              | exit code + external-loop run receipt stage                       | Mesh/Franklin narrative lock rows                  |
| Health catalog spine            | `cells/health/scripts/health_cell_gamp5_validate.sh --skip-cargo-test`                   | script logs + stage receipt                                       | `wiki/Qualification-Catalog.md` GAMP5 catalog rows |
| Franklin admin driver smoke     | `cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh` (`FRANKLIN_GAMP5_SMOKE=1`) | `cells/health/evidence/franklin_mac_admin_gamp5_*.json`           | Franklin admin-cell gate                           |
| Runtime state contract          | MacFranklin app state snapshot writer                                                    | `cells/health/evidence/macfranklin_state/state_*.json`            | external-loop lifecycle gate                       |
| Outside-in screenshot game      | Rust `mac_gamp5_observer` (or MCP equivalent)                                            | `cells/health/evidence/mac_gamp5_external_loop/screenshots/*.png` | external visual observer                           |
| Expected-vs-actual visual check | Rust `mac_gamp5_observer` (or MCP equivalent)                                            | `cells/health/evidence/mac_gamp5_external_loop/visual/*.json`     | state visual qualification                         |
| Signed game receipt             | Rust `mac_gamp5_observer` (or MCP equivalent)                                            | `cells/health/evidence/mac_gamp5_external_loop/receipts/*.json`   | append-only game receipt chain                     |
| Owner signoff pack              | `cells/franklin/scripts/mac_gamp5_signoff_pack.sh`                                       | `cells/health/evidence/mac_gamp5_signoff/*/signoff_manifest.json` | owner monitored signoff                            |


## Fail-closed requirements

- Any non-zero stage in external-loop orchestrator is `REFUSED`.
- Any unresolved state mismatch (`expected`/`actual`) is `REFUSED` until a new passing receipt records `CURE`.
- `ALIVE` may only be claimed after the runtime game chain is green and a state snapshot confirms it.