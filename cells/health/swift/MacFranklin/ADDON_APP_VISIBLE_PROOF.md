# Add-on: MacFranklin.app — visible proof (what the expert-cell plan did *not* ship)

## Why you saw “no output” and no running app

The **MacFranklin Expert Cell** integration plan added **governance docs**, **MCP tools**, **JSON schemas**, and a **NATS `mac_cell_bridge`** binary. None of that **starts** the GUI, **installs** the app in `/Applications`, or **proves** a window is open. If you expected a running **MacFranklin** (Gaia Franklin) app from that work alone, that expectation was **wrong** — not because of hidden success, but because **that scope was never the deliverable**.

This add-on closes the gap: **one script** that prints **hard terminal output** and runs **`open`** on the built `.app` so you can **see** the Dock icon and UI on a normal macOS session.

## What “proof” means (three layers)

| Layer | What you see | How you know it is real |
|-------|----------------|-------------------------|
| **1. Terminal** | Lines from `open_macfranklin_app.sh` ending in `OK:` | Text you can copy; **not** a simulated transfer or fake receipt |
| **2. GUI** | MacFranklin in Dock / menu bar | Requires an **interactive** Mac login session (SSH without display will **not** show a window) |
| **3. GAMP5** | New `cells/health/evidence/franklin_mac_admin_gamp5_*.json` after **Run** in the app | Same files the MCP tools read; **exit codes** and files on disk |

## One command (from repo root)

```bash
zsh cells/health/swift/MacFranklin/open_macfranklin_app.sh
```

Or set the tree explicitly:

```bash
export GAIAFTCL_REPO_ROOT="/absolute/path/to/FoT8D"
zsh "$GAIAFTCL_REPO_ROOT/cells/health/swift/MacFranklin/open_macfranklin_app.sh"
```

**Headless / SSH only:** the script still **builds** and prints paths; `open` may fail or do nothing useful without Aqua. Use MCP + `franklin_run_mac_gamp5` for **driver** proof without UI, or run this script **on the Mac desktop**.

## What we are not claiming

- We are **not** claiming mining, exchange, or mesh success — only **build + open + same driver path** as [`TERMINAL_DRIVER_CANONICAL.md`](../../../franklin/docs/TERMINAL_DRIVER_CANONICAL.md).
- We are **not** replacing your Qualification-Catalog sign-off; this is **operator visibility**, not QMS.

## Relation to Cursor MCP

MCP runs the Rust binary **`target/release/macfranklin_mcp_server`** — that is **not** the `.app`. Use **both**: app for eyes, MCP for agents. See [`mcp/MCP_CURSOR.md`](mcp/MCP_CURSOR.md).
