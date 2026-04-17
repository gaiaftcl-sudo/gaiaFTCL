#!/usr/bin/env python3
"""Ensure evidence/discord/RELEASE_C4_SEMANTICS.md exists (GAIA_BASE or template)."""
from __future__ import annotations

import argparse
import os
import shutil
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", type=Path, required=True)
    args = ap.parse_args()
    root: Path = args.repo_root
    target = root / "evidence" / "discord" / "RELEASE_C4_SEMANTICS.md"
    if target.is_file() and target.stat().st_size > 0:
        print(f"CALORIE: C4 semantics already present: {target}")
        return 0

    gaia_base = os.environ.get("GAIA_BASE", "").strip()
    if gaia_base:
        alt = Path(gaia_base) / "evidence" / "discord" / "RELEASE_C4_SEMANTICS.md"
        if alt.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(alt, target)
            print(f"CALORIE: copied C4 semantics from GAIA_BASE: {alt}")
            return 0
        alt2 = Path(gaia_base) / "GAIAOS" / "evidence" / "discord" / "RELEASE_C4_SEMANTICS.md"
        if alt2.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(alt2, target)
            print(f"CALORIE: copied C4 semantics from GAIA_BASE/GAIAOS: {alt2}")
            return 0

    fb = root / "scripts" / "templates" / "RELEASE_C4_SEMANTICS.md"
    if fb.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(fb, target)
        print(f"CALORIE: materialized C4 semantics from template: {fb}")
        return 0

    print(f"REFUSED: cannot materialize {target} (set GAIA_BASE or add scripts/templates/RELEASE_C4_SEMANTICS.md)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
