#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", type=pathlib.Path, required=True)
    ap.add_argument("--step-id", required=True)
    args = ap.parse_args()

    policy = args.repo_root / "services" / "gaiaos_ui_web" / "spec" / "self-healing-map.json"
    if not policy.exists():
        print("0")
        return 0
    data = json.loads(policy.read_text(encoding="utf-8"))
    default = int(data.get("defaults", {}).get("retry_attempts", 0))
    for row in data.get("domains", []):
        if args.step_id in row.get("step_ids", []):
            print(int(row.get("retry_attempts", default)))
            return 0
    print(default)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
