#!/usr/bin/env python3
"""
GAMP5-oriented checks for wiki/Qualification-Catalog.md (mirror of GitHub wiki page).

- Required section anchors / GAMP vocabulary (documentation traceability)
- Every github.com/.../gaiaFTCL/blob/main/<path> target must exist on disk
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
CATALOG = REPO_ROOT / "wiki" / "Qualification-Catalog.md"

# Minimum structural / GAMP5 traceability content (honest targets, not marketing)
REQUIRED_SUBSTRINGS = [
    "## 8. Framework applicability matrix",
    "### 4.5 OWL-NUTRITION",
    "### §8.2 OWL-NUTRITION v1 — framework targets",
    "GAMP 5",
    "GAMP5_LIFECYCLE.md",
    "IQ / OQ / PQ",
    "fn-n1",  # OWL-NUTRITION footnote discipline
]

BLOB_RE = re.compile(
    r"https://github\.com/gaiaftcl-sudo/gaiaFTCL/blob/main/([^)\s#?]+)"
)


def main() -> int:
    if not CATALOG.is_file():
        print(f"FAIL: missing {CATALOG}", file=sys.stderr)
        return 1

    text = CATALOG.read_text(encoding="utf-8")
    missing = [s for s in REQUIRED_SUBSTRINGS if s not in text]
    if missing:
        print("FAIL: Qualification Catalog missing required GAMP5/traceability fragments:", file=sys.stderr)
        for m in missing:
            print(f"  - {m!r}", file=sys.stderr)
        return 1
    print(f"OK: required sections / GAMP5 markers present in {CATALOG.relative_to(REPO_ROOT)}")

    paths = set()
    for m in BLOB_RE.finditer(text):
        p = m.group(1).rstrip("/")
        paths.add(p)

    broken = []
    for rel in sorted(paths):
        local = REPO_ROOT / rel
        if not local.is_file():
            broken.append((rel, str(local)))

    if broken:
        print("FAIL: blob links in catalog with no local file on disk:", file=sys.stderr)
        for rel, loc in broken:
            print(f"  - {rel} -> {loc}", file=sys.stderr)
        return 1

    print(f"OK: {len(paths)} unique /blob/main/ paths resolve under repo root")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
