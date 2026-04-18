#!/usr/bin/env python3
"""Map ~/.playwright-discord/discovered_portal_apps.json → discord_devportal_manifest.json for capture."""
from __future__ import annotations

import json
import os
import pathlib
import sys

HOME = pathlib.Path.home()
DISC = HOME / ".playwright-discord"
DISCOVERED = DISC / "discovered_portal_apps.json"
OUT = DISC / "discord_devportal_manifest.json"

# Default name → env_var for known GaiaFTCL portal labels (extend when you add apps).
# Membrane token belongs in secrets.env (DISCORD_MEMBRANE_TOKEN), not mesh game-room key.
DEFAULT_MAP = {
    "gaiaftcl": "DISCORD_APP_BOT_TOKEN",
}


def main() -> int:
    if not DISCOVERED.is_file():
        print("REFUSED: missing", DISCOVERED, file=sys.stderr)
        return 1
    doc = json.loads(DISCOVERED.read_text(encoding="utf-8"))
    apps = doc.get("apps") or []
    mapped: list[dict[str, str]] = []
    for a in apps:
        name = (a.get("name") or "").strip().lower()
        aid = (a.get("id") or "").strip()
        if not aid.isdigit():
            continue
        ev = DEFAULT_MAP.get(name)
        if not ev:
            ev = os.environ.get(f"DISCORD_MAP_{aid}", "")
        if not ev:
            print("SKIP unmapped portal name:", a.get("name"), "id=", aid, file=sys.stderr)
            continue
        mapped.append({"env_var": ev, "application_id": aid, "note": a.get("name", "")})
    if not mapped:
        print("REFUSED: no mapped apps — set names in DEFAULT_MAP or DISCORD_MAP_<id>", file=sys.stderr)
        return 1
    DISC.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"apps": mapped}, indent=2) + "\n", encoding="utf-8")
    OUT.chmod(0o600)
    print("wrote", OUT, len(mapped), "entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
