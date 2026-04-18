#!/usr/bin/env python3
"""
Deprecated entrypoint — the hunt is manifest-driven per calendar day.

Use:
  python3 scripts/vie_v2/daily_sports_hunt.py --help
  python3 scripts/vie_v2/daily_sports_hunt.py --init-manifest
  python3 scripts/vie_v2/daily_sports_hunt.py [--date YYYY-MM-DD] [--dry-run]
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
    target = Path(__file__).resolve().with_name("daily_sports_hunt.py")
    raise SystemExit(subprocess.call([sys.executable, str(target)] + sys.argv[1:]))
