#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_registry_ids(repo_root: Path) -> list[str]:
    reg = repo_root / "services" / "discord_frontier" / "game_room_registry.json"
    data = json.loads(reg.read_text(encoding="utf-8"))
    ids: list[str] = []
    for e in data.get("entries", []):
        if e.get("kind") == "game_room" and e.get("enabled", True):
            gid = str(e.get("id") or "").strip().replace("_", "-")
            if gid:
                ids.append(gid)
    if "sports-vortex" not in ids:
        ids.append("sports-vortex")
    return sorted(set(ids))


def main() -> int:
    ap = argparse.ArgumentParser(description="Update PLAYWRIGHT_MESH_GAME_CAPTURE.json from registry ids.")
    ap.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument("--run-id", default=f"playwright-run-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}")
    ap.add_argument("--evidence", default="", help="Optional evidence path or URL for this run.")
    ap.add_argument("--mark-live", default="", help="Comma list of game ids to mark live_captured=true.")
    ap.add_argument("--note", default="", help="Optional run note (skips, blockers, auth gates).")
    args = ap.parse_args()

    root = args.repo_root.resolve()
    out = root / "evidence" / "discord_game_rooms" / "PLAYWRIGHT_MESH_GAME_CAPTURE.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    existing = {}
    if out.is_file():
        try:
            existing = json.loads(out.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            existing = {}

    ids = load_registry_ids(root)
    live = {x.strip() for x in args.mark_live.split(",") if x.strip()}
    games = existing.get("games") if isinstance(existing.get("games"), dict) else {}
    result_games: dict[str, dict] = {}
    for gid in ids:
        prev = games.get(gid, {}) if isinstance(games.get(gid), dict) else {}
        is_live = gid in live
        result_games[gid] = {
            "live_captured": is_live,
            "evidence": args.evidence or prev.get("evidence"),
            "last_run_ts_utc": utc_now(),
            "required_playwright_spec": "services/gaiaos_ui_web/tests/discord/*.spec.ts",
            "note": args.note or prev.get("note"),
        }

    payload = {
        "run_id": args.run_id,
        "ts_utc": utc_now(),
        "driver": "playwright",
        "games": result_games,
    }
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(out)
    print(f"games={len(result_games)} live={sum(1 for g in result_games.values() if g['live_captured'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
