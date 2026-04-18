#!/usr/bin/env python3
"""Emit config/discord_forest_provision_targets.json from game_room_registry.json."""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REG = ROOT / "services" / "discord_frontier" / "game_room_registry.json"
OUT = ROOT / "config" / "discord_forest_provision_targets.json"


def main() -> int:
    if not REG.is_file():
        print("REFUSED: missing", REG, file=sys.stderr)
        return 1
    reg = json.loads(REG.read_text(encoding="utf-8"))
    targets: list[dict] = []

    targets.append(
        {
            "env_var": "DISCORD_APP_BOT_TOKEN",
            "portal_app_name": "GaiaFTCL",
            "create_if_missing": False,
            "skip_token_reset": True,
        }
    )

    ops = [
        e
        for e in reg.get("entries", [])
        if e.get("kind") == "operational" and e.get("enabled") and e.get("env_token_var")
    ]
    ops.sort(key=lambda x: x.get("id", ""))
    for e in ops:
        i = e["id"]
        targets.append(
            {
                "env_var": e["env_token_var"],
                "portal_app_name": f"GaiaFTCL {i}",
                "create_if_missing": True,
            }
        )

    rooms = [
        e
        for e in reg.get("entries", [])
        if e.get("kind") == "game_room" and e.get("enabled") and e.get("env_token_var")
    ]
    rooms.sort(key=lambda x: x.get("id", ""))
    for e in rooms:
        i = e["id"]
        targets.append(
            {
                "env_var": e["env_token_var"],
                "portal_app_name": f"GaiaFTCL {i}",
                "create_if_missing": True,
            }
        )

    doc = {"version": 1, "description": "Developer Portal loop: one Discord Application per row.", "targets": targets}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print("wrote", OUT, len(targets), "targets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
