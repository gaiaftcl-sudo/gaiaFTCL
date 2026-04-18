# Phase 6 — S4 Observable Layer (AppleScript + substrate)

The Mac is the **observer**. Discord is the **surface**. AppleScript drives the **Discord desktop app** via Accessibility (Quick Switcher ⌘K).

## Read first (codebase)

- **Membrane routing:** `services/discord_frontier/discord_app/main.py` — optional per-channel NATS membrane (`DISCORD_MEMBRANE_ENABLED` + `DISCORD_MEMBRANE_ROUTING`); slash **`/mesh`** hits mesh peer registry; message path goes through `CrystalDiscordCell` + membrane dispatch when configured.
- **Substrate checks:** `tests/discord_frontier/test_substrate.py` — same `GAIAFTCL_GATEWAY` + optional `GAIAFTCL_INTERNAL_KEY` / `GAIAFTCL_INTERNAL_SERVICE_KEY`.
- **Channel → game_room:** `services/discord_frontier/shared/cell_base.py` — `parse_channel_to_game_room` (e.g. `owl-protocol` → `owl_protocol`, `receipts` → `receipt_wall`, `ask-franklin` → `ask_franklin`).

There is **no** `services/discord_frontier/membrane/main.py`; membrane behavior lives in **`discord_app/main.py`** and workers under `workers/`.

## macOS setup

1. **Discord** installed and **running**.
2. **Accessibility:** System Settings → Privacy & Security → **Accessibility** → add **Terminal** or **iTerm** (and **Script Editor** if you export the observer/heartbeat as an app).
3. **Developer Mode** in Discord → copy **Guild** and **Channel** IDs.

## Channel IDs (automation)

**Option A — API discovery (recommended):**

```bash
export DISCORD_GUILD_ID='…'
export DISCORD_MEMBRANE_TOKEN='…'   # or DISCORD_APP_BOT_TOKEN / DISCORD_BOT_TOKEN_OWL
python3 tests/discord_frontier/applescript/discover_channel_ids.py
```

Writes `tests/discord_frontier/applescript/channel_ids.env`.

**Option B — manual:** copy `applescript/channel_ids.env.example` → `applescript/channel_ids.env` and fill in.

**Option C — shell exports:** export `DISCORD_GUILD_ID`, `CHANNEL_ID_OWL_PROTOCOL`, … then run `run_phase6_live.sh` (it will write `channel_ids.env`).

## Gateway tunnel

SSH local forward to **`fot-mcp-gateway-mesh`** container IP port **8803** (see `run_phase6_live.sh` / Phase 2).

```bash
export GAIAFTCL_GATEWAY=http://127.0.0.1:18803
export GAIAFTCL_INTERNAL_KEY=   # optional; set if gateway enforces it
```

`run_phase6_live.sh` writes `applescript/phase6_gateway.env` for helpers.

## Run Phase 6

From repo root:

```bash
bash tests/discord_frontier/run_phase6_live.sh
```

## Jump to a channel (deep link)

```bash
set -a; source tests/discord_frontier/applescript/channel_ids.env; set +a
bash tests/discord_frontier/applescript/gaia_jump.sh "$CHANNEL_ID_OWL_PROTOCOL"
```

## Background heartbeat (dings on new CALORIE-shaped claims)

**Recommended (terminal, no Script Editor):**

```bash
bash tests/discord_frontier/applescript/gaia_vortex_heartbeat_daemon.sh
```

**AppleScript `on idle`:** `gaia_vortex_heartbeat.scpt` only idles when saved as a **stay-open Application** in Script Editor. Set env **`PHASE6_APPLE_DIR`** to the `applescript/` directory before launch, or pass that POSIX path as **argv[1]** when opening the applet.

Mesh gateway **`GET /vqbit/torsion`**: collection **`vqbit_measurements`** in **`gaiaos`** (`VQBIT_MEASUREMENTS_COLLECTION`). **`system_state`**: `NOHARM` \| `STRESSED` \| `APPROACHING_LIMIT` \| `COLLAPSED`. Fewer than two rows → **`current_torsion`** `0.0` (float) and **`note`**: `insufficient measurements for torsion`.

## Observer

- **`gaia_observer.scpt`:** same stay-open Application requirement as heartbeat.
- **`gaia_observer_poll.sh`:** one-shot; wrap in `while sleep 30; do …; done` if desired.

## Permissions

If keystrokes do nothing, re-check **Accessibility** for the shell host and focus Discord on the correct monitor/Space.

Calories or Cures.
