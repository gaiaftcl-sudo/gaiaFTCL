#!/usr/bin/env python3
"""
Resolve Discord text channel IDs by name (Phase 6 automation).
Requires: DISCORD_GUILD_ID, and a bot token (DISCORD_MEMBRANE_TOKEN | DISCORD_APP_BOT_TOKEN | DISCORD_BOT_TOKEN_OWL).

Writes applescript/channel_ids.env next to this file.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Slugs we search for (lowercase); first match wins per key
TARGETS: dict[str, tuple[str, ...]] = {
    "CHANNEL_ID_OWL_PROTOCOL": ("owl-protocol", "owl_protocol", "owl protocol"),
    "CHANNEL_ID_DISCOVERY": ("discovery", "game-room-discovery"),
    "CHANNEL_ID_GOVERNANCE": ("governance",),
    "CHANNEL_ID_TREASURY": ("treasury",),
    "CHANNEL_ID_SOVEREIGN_MESH": ("sovereign-mesh", "sovereign_mesh", "sovereign mesh"),
    "CHANNEL_ID_RECEIPTS": ("receipts", "receipt-wall", "receipt_wall"),
    "CHANNEL_ID_ASK_FRANKLIN": ("ask-franklin", "ask_franklin", "franklin", "ask franklin"),
}


def main() -> int:
    guild = (os.environ.get("DISCORD_GUILD_ID") or "").strip()
    token = (
        os.environ.get("DISCORD_MEMBRANE_TOKEN")
        or os.environ.get("DISCORD_APP_BOT_TOKEN")
        or os.environ.get("DISCORD_BOT_TOKEN_OWL")
        or ""
    ).strip()
    if not guild or not token:
        print(
            "Need DISCORD_GUILD_ID and one of "
            "DISCORD_MEMBRANE_TOKEN, DISCORD_APP_BOT_TOKEN, DISCORD_BOT_TOKEN_OWL",
            file=sys.stderr,
        )
        return 1

    req = urllib.request.Request(
        f"https://discord.com/api/v10/guilds/{guild}/channels",
        headers={"Authorization": f"Bot {token}"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            channels = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(e.read().decode()[:500], file=sys.stderr)
        return 1

    by_lower: dict[str, str] = {}
    for ch in channels:
        if ch.get("type") != 0:
            continue
        name = (ch.get("name") or "").strip().lower()
        if name:
            by_lower.setdefault(name, str(ch["id"]))

    out_lines = [f"DISCORD_GUILD_ID={guild}"]
    missing: list[str] = []
    for var, aliases in TARGETS.items():
        found: str | None = None
        for alias in aliases:
            if alias.lower() in by_lower:
                found = by_lower[alias.lower()]
                break
        if found:
            out_lines.append(f"{var}={found}")
        else:
            out_lines.append(f"{var}=")
            missing.append(var)

    root = Path(__file__).resolve().parent
    env_path = root / "channel_ids.env"
    env_path.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    print(f"Wrote {env_path}")
    if missing:
        print("Unmatched (fill manually):", ", ".join(missing), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
