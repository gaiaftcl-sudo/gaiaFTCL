#!/usr/bin/env python3
"""
Superseded by Rust: `target/release/fo-franklin verify-pins` (`fo_cell_substrate`). Kept for reference.

Verify on-disk script SHA-256s match cells/franklin/pins.json.
Exit 0 = all match; 1 = mismatch or missing file.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PINS = REPO / "cells" / "franklin" / "pins.json"


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if not PINS.is_file():
        print("REFUSED: missing", PINS, file=sys.stderr)
        return 1
    data = json.loads(PINS.read_text(encoding="utf-8"))
    scripts = data.get("orchestrator_scripts") or {}
    if not scripts:
        print("REFUSED: pins.json has empty orchestrator_scripts — run refresh_franklin_pins.sh", file=sys.stderr)
        return 1
    bad = 0
    for rel, want in sorted(scripts.items()):
        p = REPO / rel
        if not p.is_file():
            print("MISSING", p, file=sys.stderr)
            bad = 1
            continue
        got = sha256_file(p)
        if got != want:
            print(f"MISMATCH {rel}\n  want {want}\n  got  {got}", file=sys.stderr)
            bad = 1
        else:
            print("OK", rel, got[:12] + "…")
    # admin-cell path file
    exp = REPO / "cells" / "health" / ".admincell-expected" / "orchestrator.sha256"
    if exp.is_file():
        line = exp.read_text(encoding="utf-8").strip()
        hrel = "cells/health/scripts/health_full_local_iqoqpq_gamp.sh"
        if hrel in scripts and line != scripts[hrel]:
            print(f"MISMATCH {exp} (must match pins[{hrel!r}])", file=sys.stderr)
            bad = 1
        else:
            print("OK", exp, "(matches main orchestrator pin)")
    else:
        print("WARN: no", exp, "(optional until refresh_franklin_pins.sh has been run)", file=sys.stderr)
    return bad


if __name__ == "__main__":
    raise SystemExit(main())
