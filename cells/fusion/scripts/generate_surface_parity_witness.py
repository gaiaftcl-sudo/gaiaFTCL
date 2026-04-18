#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    capture = root / "evidence" / "discord_game_rooms" / "PLAYWRIGHT_MESH_GAME_CAPTURE.json"
    if not capture.is_file():
        raise SystemExit("missing PLAYWRIGHT_MESH_GAME_CAPTURE.json")
    data = json.loads(capture.read_text(encoding="utf-8"))
    games = data.get("games") or {}
    validation = root / "evidence" / "discord_game_rooms" / "game_validation_20260331_132531.json"
    available = set()
    if validation.is_file():
        try:
            v = json.loads(validation.read_text(encoding="utf-8"))
            available = set((v.get("game_rooms") or {}).keys())
        except (json.JSONDecodeError, OSError):
            available = set()
    reg_to_validation = {
        "atc": "atc-ops",
        "biology-cures": "biology-cures",
        "crypto-risk": "crypto-risk",
        "nuclear-fusion": "nuclear-fusion",
        "token-economics": "token-economics",
        "logistics-chain": "logistics",
        "quantum-closure": "quantum-closure",
        "robotics-ops": "robotics",
        "telecom-mesh": "telecom",
        "med": "medical",
        "law": "law",
        "climate-accounting": "climate",
        "neuro-clinical": "neuro-clinical",
        "sports-vortex": "sports-vortex",
    }
    total = 0
    bad = []
    for gid, row in games.items():
        if not isinstance(row, dict):
            continue
        mapped = reg_to_validation.get(gid, gid)
        if available and mapped not in available:
            continue
        total += 1
        if not bool(row.get("live_captured")):
            bad.append(gid)
    out = {
        "schema": "surface_parity_witness_v1",
        "parity_mode": "pipeline_discord_mesh_games",
        "ts_utc": utc_now(),
        "source": str(capture),
        "driver": data.get("driver"),
        "games_total": total,
        "games_live": total - len(bad),
        "missing_live_games": bad,
        "divergence_count": len(bad),
        "terminal": "CALORIE" if len(bad) == 0 else "PARTIAL",
    }
    path = root / "evidence" / "parity" / "SURFACE_PARITY_WITNESS.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(path)
    print(json.dumps({"divergence_count": out["divergence_count"], "terminal": out["terminal"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
