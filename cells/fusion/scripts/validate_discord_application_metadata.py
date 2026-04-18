#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Fetch Discord Application object (GET /applications/@me) and decode flags for Embedded Activities.

Env:
  DISCORD_APP_BOT_TOKEN or DISCORD_BOT_TOKEN — Bot token (required for API call)
  C4_DISCORD_ACTIVITIES_URL — optional; recorded in witness for S4 traceability

Exit:
  0 — success (CALORIE or SKIPPED when no token)
  1 — HTTP/API failure or REFUSED (embedded flag missing when C4_REQUIRE_DISCORD_EMBEDDED_FLAGS=1)

Artifact: evidence/discord/DISCORD_APPLICATION_METADATA_WITNESS.json
"""
from __future__ import annotations

import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _truthy(env: str | None) -> bool:
    if not env:
        return False
    return env.strip().lower() in ("1", "true", "yes", "on")


# Must match spec/discord_embedded_activities_platform.json
FLAG_DEFS: list[tuple[str, int]] = [
    ("EMBEDDED_RELEASED", 1 << 1),
    ("GATEWAY_PRESENCE", 1 << 12),
    ("GATEWAY_GUILD_MEMBERS", 1 << 14),
    ("EMBEDDED", 1 << 17),
    ("GATEWAY_MESSAGE_CONTENT", 1 << 18),
    ("APPLICATION_COMMAND_BADGE", 1 << 23),
]


def decode_flags(flags: int) -> dict[str, bool]:
    out: dict[str, bool] = {}
    for name, mask in FLAG_DEFS:
        out[name] = bool(flags & mask)
    return out


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    out_path = repo / "evidence" / "discord" / "DISCORD_APPLICATION_METADATA_WITNESS.json"
    token = (os.environ.get("DISCORD_APP_BOT_TOKEN") or os.environ.get("DISCORD_BOT_TOKEN") or "").strip()
    require_embedded = _truthy(os.environ.get("C4_REQUIRE_DISCORD_EMBEDDED_FLAGS"))
    activities_url = (os.environ.get("C4_DISCORD_ACTIVITIES_URL") or "").strip()

    if not token:
        doc = {
            "schema": "discord_application_metadata_witness_v1",
            "ts_utc": utc_now(),
            "terminal": "SKIPPED",
            "reason": "no_bot_token_in_env",
            "discord_embedded_activity_eligible": None,
            "require_embedded_flags_env": require_embedded,
        }
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        print(out_path)
        return 0

    url = "https://discord.com/api/v10/applications/@me"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bot {token}",
            "User-Agent": "GaiaFTCL-invariant (discord metadata witness)",
        },
        method="GET",
    )
    try:
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(req, timeout=30, context=ctx) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            status = resp.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace") if e.fp else ""
        doc = {
            "schema": "discord_application_metadata_witness_v1",
            "ts_utc": utc_now(),
            "terminal": "REFUSED",
            "http_status": e.code,
            "error_body_excerpt": body[:2000],
            "discord_embedded_activity_eligible": False,
        }
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        print(out_path, file=sys.stderr)
        return 1
    except (urllib.error.URLError, OSError) as e:
        doc = {
            "schema": "discord_application_metadata_witness_v1",
            "ts_utc": utc_now(),
            "terminal": "REFUSED",
            "http_status": 0,
            "error": str(e),
            "discord_embedded_activity_eligible": False,
        }
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        print(out_path, file=sys.stderr)
        return 1

    try:
        app = json.loads(raw)
    except json.JSONDecodeError:
        doc = {
            "schema": "discord_application_metadata_witness_v1",
            "ts_utc": utc_now(),
            "terminal": "REFUSED",
            "http_status": status,
            "error": "invalid_json",
            "discord_embedded_activity_eligible": False,
        }
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        return 1

    flags = int(app.get("flags") or 0)
    decoded = decode_flags(flags)
    embedded_ok = bool(decoded.get("EMBEDDED"))
    terminal = "CALORIE"
    blockers: list[str] = []
    if require_embedded and not embedded_ok:
        terminal = "REFUSED"
        blockers.append("discord_application_missing_EMBEDDED_flag")
    doc = {
        "schema": "discord_application_metadata_witness_v1",
        "ts_utc": utc_now(),
        "terminal": terminal,
        "http_status": status,
        "endpoint": "/applications/@me",
        "application_id": str(app.get("id") or ""),
        "name": str(app.get("name") or ""),
        "flags": flags,
        "flags_decoded": decoded,
        "discord_embedded_activity_eligible": embedded_ok,
        "c4_discord_activities_url": activities_url or None,
        "require_embedded_flags_env": require_embedded,
        "blockers": blockers,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(out_path)
    return 0 if terminal == "CALORIE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
