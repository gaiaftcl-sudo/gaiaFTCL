# MacFranklin + Cursor (MCP) — step-by-step

This folder exposes **Franklin GAMP5** the same way the MacFranklin app does: **real shell processes**, evidence under `cells/health/evidence/`, no stubbed “success” paths.

## A. What is what (debug map)

1. **Cursor MCP (stdio)** — Cursor starts the **Rust MCP binary** (`target/release/macfranklin_mcp_server`) and talks over stdin/stdout. **No network port** is required for this. If tools fail, check binary path and `GAIAFTCL_REPO_ROOT`.
2. **MacFranklin.app** — Same repo root + same driver script `cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh`. Use the app to watch logs and “Open evidence folder”; use Cursor with MCP to drive the same flow from the agent.
3. **Mesh / Fusion HTTP MCP (`:8803`)** — Separate stack: `fot_mcp_gateway` / GaiaFusion loopback, **not** the stdio server in this folder. For a **remote head** you often **SSH port-forward** `8803` (or the host your operator docs use) to `127.0.0.1:8803` and set `MCP_BASE_URL` / `MCP_GATEWAY_URL` for HTTP clients. That path does not replace the MacFranklin stdio MCP; they solve different connection shapes.
4. **NATS** — If your runbook says “bridge NATS to the Mac,” that is **another** tunnel (e.g. local `14222` → head `4222`), unrelated to **Cursor’s stdio MCP** (unless your tooling explicitly wires NATS into the same client).

## B. One-time: build Rust MCP server

From repo root:

```bash
cargo build -p macfranklin_mcp_server --release
```

Binary output: `target/release/macfranklin_mcp_server`.

## C. Wire Cursor: user `mcp.json`

Use an absolute path to the Rust binary, and set `**GAIAFTCL_REPO_ROOT**` to your tree.

Example (replace `REPO`):

```json
{
  "mcpServers": {
    "macfranklin": {
      "command": "REPO/target/release/macfranklin_mcp_server",
      "args": [],
      "env": {
        "GAIAFTCL_REPO_ROOT": "REPO"
      }
    }
  }
}
```

- Global file: `~/.cursor/mcp.json` (or the path Cursor’s Settings → MCP shows on your build).
- Restart Cursor after editing.

## D. Prove it in three checks

1. In Cursor, open MCP and confirm the **macfranklin** Rust server is connected (no spawn error in the log).
2. Call tool `**franklin_repo_status`** — `ok_for_gamp5` should be `true` when the tree matches MacFranklin’s pin script.
3. Call `**franklin_run_mac_gamp5**` with `smoke: true` — then list/read evidence with `**franklin_list_evidence**` / `**franklin_read_text_file**`.
4. Required full proof before signoff: `**franklin_gamp5_validate**` (long run; same script as `zsh cells/franklin/scripts/franklin_gamp5_validate.sh`).

## E. HTTP MCP on 8803 (mesh, separate stack)

Not required for this stdio server. If you are debugging the **gateway** path only:

- Point tools at `http://127.0.0.1:8803` (or your tunneled URL).
- If the head is remote, use your operator SSH `-L` so **local** `127.0.0.1:8803` reaches the process that serves `/health` on the head (see `cells/fusion/scripts/preflight_mcp_gateway.sh` and your fleet runbook for the exact host/port).

This doc is the **wiring and port mental model**; the **truth** for each run is still process exit codes + files under `cells/health/evidence/`.

## F. Tool allowlist + permissions manifest (expert cell, Rust MCP)

**What may run (stdio MCP, default):** only the tools exposed by the Rust binary `macfranklin_mcp_server` — real `sh` / `zsh` / `cargo` / `swift` / `fo-health` with **fixed** argv.

**What must not be added ad hoc:** no arbitrary user shell, no `curl` / `rm` / deploy except via operator-documented **separate** processes (e.g. `MACFRANKLIN_OPERATOR=1` in your runbook, not in this server).

**No Python in Mac app lane:** MCP server and observer path are Rust binaries; no Python/PyPI dependency is required for MacFranklin app + MCP operation.


| MCP tool                                                                                                 | Qualification / catalog surface                                                                                                                                                  |
| -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fo_health_gamp5_catalog`                                                                                | `fo-health gamp5-catalog` — `[wiki/Qualification-Catalog.md](../../../../../wiki/Qualification-Catalog.md)` structural parity (same gate as `health_cell_gamp5_validate` step 2) |
| `health_cell_gamp5_validate`                                                                             | Full health cell: wiki lint, catalog, OWL / peptide, `cargo test` (or `--skip-cargo-test`) per script                                                                            |
| `franklin_gamp5_validate`                                                                                | Franklin pack (Swift + Franklin scripts)                                                                                                                                         |
| `franklin_run_mac_gamp5` / `franklin_repo_status` / `franklin_list_evidence` / `franklin_read_text_file` | `franklin_mac_admin_gamp5` receipt family under `cells/health/evidence/`                                                                                                         |
| `franklin_mesh_narrative_lock`                                                                           | `[cells/franklin/docs/KLEIN_CLOSURE.md](../../../../franklin/docs/KLEIN_CLOSURE.md)` / mesh topology                                                                             |
| `franklin_lithography_entrypoints`                                                                       | Catalog **§6** + `cells/lithography/` pointers (read-only)                                                                                                                       |
| `franklin_bounded_cargo`                                                                                 | `fo_cell_substrate` only — `build --release` or `test`                                                                                                                           |
| `franklin_swift_test_macfranklin`                                                                        | `cells/health/swift/MacFranklin` package tests                                                                                                                                   |
| `franklin_gamp5_oq_ring2`                                                                                | Optional Ring-2: `[scripts/gamp5_oq.sh](../../../../../scripts/gamp5_oq.sh)` (see `cells/health/docs/GAMP5_RING2_REPO_SCRIPTS.md`)                                               |
| `franklin_wellbeing_status`                                                                              | Read-only: recent `franklin_mac_admin_gamp5_*.json` + `genesys_*.json` metadata for rack / last-good                                                                             |
| `franklin_run_external_loop`                                                                             | Owner-Mac external loop: consent + clone/update + build/launch + core games                                                                                                      |
| `franklin_capture_screenshot`                                                                            | External observer screenshot artifact for state game evidence                                                                                                                    |
| `franklin_runtime_state_latest`                                                                          | Reads app self-addressable runtime state snapshot (`macfranklin_runtime_state_v1`)                                                                                               |
| `franklin_visual_validate`                                                                               | Expected-vs-actual structural visual check + metrics JSON                                                                                                                        |
| `franklin_publish_game_receipt`                                                                          | Append-only signed game receipt (`mac_gamp5_game_receipt_v1`)                                                                                                                    |
| (binary, not MCP)                                                                                        | `[mac_cell_bridge](../../../../franklin/services/mac_cell_bridge/README.md)` — NATS liveness only; **not** a substitute for GAMP5                                                |


**More context:** [§3 path table](../../../../franklin/docs/PATH_TABLE_S3.md), [normative vs roadmap](../../../../franklin/docs/NORMATIVE_VS_ROADMAP.md), [external-loop game mapping](../../../../franklin/docs/MAC_GAMP5_EXTERNAL_LOOP_GAMES.md).