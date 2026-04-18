#!/usr/bin/env python3
"""
Head / consumer: subscribe to gaiaftcl.fusion.cell.status.v1, merge by cell_id into
evidence/fusion_control/fusion_fleet_snapshot.json (compact file, no JSONL on NATS).

Requires: pip install nats-py
Env:
  NATS_URL   default nats://127.0.0.1:4222
  GAIA_ROOT  repo root (default: parent of scripts/)
  FUSION_CELL_STATUS_NATS_SUBJECT  default gaiaftcl.fusion.cell.status.v1
"""
from __future__ import annotations

import asyncio
import json
import os
import tempfile
from pathlib import Path
from typing import Any

try:
    import nats  # type: ignore
except ImportError:
    raise SystemExit("REFUSED: pip install nats-py")

SUBJECT = os.environ.get("FUSION_CELL_STATUS_NATS_SUBJECT", "gaiaftcl.fusion.cell.status.v1").strip()
SCHEMA_ROW = "gaiaftcl_fusion_fleet_snapshot_v1"


def snapshot_path() -> Path:
    root = os.environ.get("GAIA_ROOT", "").strip()
    if not root:
        root = str(Path(__file__).resolve().parents[1])
    return Path(root) / "evidence" / "fusion_control" / "fusion_fleet_snapshot.json"


def load_snapshot(p: Path) -> dict[str, Any]:
    if not p.is_file():
        return {
            "schema": SCHEMA_ROW,
            "updated_at_utc": "",
            "cells": {},
        }
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"schema": SCHEMA_ROW, "updated_at_utc": "", "cells": {}}


def validate_status(msg: dict[str, Any]) -> bool:
    if msg.get("schema") != "gaiaftcl_fusion_cell_status_v1":
        return False
    cid = msg.get("cell_id")
    if not isinstance(cid, str) or not cid.strip():
        return False
    return True


def merge_write(p: Path, cell_id: str, status: dict[str, Any]) -> None:
    from datetime import datetime, timezone

    data = load_snapshot(p)
    cells = data.get("cells")
    if not isinstance(cells, dict):
        cells = {}
    cells[cell_id] = status
    data["cells"] = cells
    data["schema"] = SCHEMA_ROW
    data["updated_at_utc"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    p.parent.mkdir(parents=True, exist_ok=True)
    raw = json.dumps(data, indent=2, sort_keys=False)
    fd, tmp = tempfile.mkstemp(dir=str(p.parent), prefix=".fusion_fleet_snapshot.", suffix=".tmp")
    try:
        os.write(fd, raw.encode("utf-8"))
        os.close(fd)
        os.replace(tmp, p)
    except OSError:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


async def main() -> None:
    nurl = os.environ.get("NATS_URL", "nats://127.0.0.1:4222").strip()
    out = snapshot_path()
    nc = await nats.connect(nurl)

    async def handler(msg) -> None:
        try:
            payload = json.loads(msg.data.decode("utf-8"))
            if not validate_status(payload):
                print("REFUSED invalid cell.status payload")
                return
            cid = str(payload["cell_id"])
            merge_write(out, cid, payload)
            print("CALORIE fleet snapshot", cid, "->", out)
        except (json.JSONDecodeError, OSError, KeyError, TypeError) as e:
            print("REFUSED", e)

    await nc.subscribe(SUBJECT, cb=handler)
    print(f"CALORIE fusion fleet snapshot subscriber {SUBJECT} @ {nurl} -> {out}")
    while True:
        await asyncio.sleep(3600)


if __name__ == "__main__":
    asyncio.run(main())
