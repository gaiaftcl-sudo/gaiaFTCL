#!/usr/bin/env python3
# Superseded by Rust: `target/release/fo-franklin validate-receipt-v1` (crate `fo_cell_substrate`). Kept for reference.
"""
Validate a Franklin `franklin_mac_admin_gamp5_receipt_v1` JSON file against
the repo schema (structural + required keys; stdlib only).

Usage:
  python3 validate_franklin_receipt_v1.py <path-to-receipt.json>
  cat receipt.json | python3 validate_franklin_receipt_v1.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REQUIRED = (
    "schema",
    "ts_utc",
    "git_short_sha",
    "repo_root",
    "zero_human_automation",
    "franklin_mac_admin_cell_role",
    "smoke_mode",
    "final_exit",
    "phases",
    "note",
)

SCHEMA_CONST = "franklin_mac_admin_gamp5_receipt_v1"
ROLE_CONST = "self_heal_mesh_head_game_loop"


def load_json(path: str | None) -> object:
    if path and path != "-":
        p = Path(path)
        with p.open(encoding="utf-8") as f:
            return json.load(f)
    return json.load(sys.stdin)


def validate(obj: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(obj, dict):
        return ["root must be a JSON object"]
    d = obj
    for k in REQUIRED:
        if k not in d:
            errors.append(f"missing required key: {k}")
    if errors:
        return errors
    if d.get("schema") != SCHEMA_CONST:
        errors.append(f"schema must be {SCHEMA_CONST!r}, got {d.get('schema')!r}")
    if d.get("franklin_mac_admin_cell_role") != ROLE_CONST:
        errors.append(f"franklin_mac_admin_cell_role must be {ROLE_CONST!r}")
    if d.get("zero_human_automation") is not True:
        errors.append("zero_human_automation must be true")
    if not isinstance(d.get("smoke_mode"), bool):
        errors.append("smoke_mode must be a boolean")
    if not isinstance(d.get("final_exit"), int):
        errors.append("final_exit must be an integer")
    if not isinstance(d.get("phases"), list):
        errors.append("phases must be an array")
    else:
        for i, ph in enumerate(d["phases"]):
            if not isinstance(ph, dict):
                errors.append(f"phases[{i}] must be an object")
                continue
            if "name" not in ph or "exit" not in ph:
                errors.append(f"phases[{i}] must have name and exit")
            elif not isinstance(ph["name"], str) or not ph["name"].strip():
                errors.append(f"phases[{i}].name must be a non-empty string")
            elif not isinstance(ph["exit"], int):
                errors.append(f"phases[{i}].exit must be an integer")
    ts = d.get("ts_utc", "")
    if not isinstance(ts, str) or not re.match(
        r"^\d{4}-\d{2}-\d{2}T\d{6}Z$", ts
    ):
        errors.append(
            "ts_utc must match YYYY-MM-DDTHHMMSSZ (Franklin script format)"
        )
    if "tau_block_height" in d:
        tb = d["tau_block_height"]
        if not isinstance(tb, int) or tb < 0:
            errors.append("tau_block_height must be a non-negative integer if present")
    return errors


def main() -> int:
    argv = sys.argv[1:]
    path = argv[0] if argv else None
    try:
        data = load_json(path)
    except (OSError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    errs = validate(data)
    if errs:
        for e in errs:
            print(f"INVALID: {e}", file=sys.stderr)
        return 1
    print("OK: franklin_mac_admin_gamp5_receipt_v1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
