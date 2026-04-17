#!/usr/bin/env python3
"""Keep last value per KEY in a KEY=value fragment (e.g. discord-forest.captured.fragment.env)."""
from __future__ import annotations

import pathlib
import sys


def main() -> int:
    p = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if not p or not p.is_file():
        print("usage: dedupe_env_fragment.py <path>", file=sys.stderr)
        return 1
    kv: dict[str, str] = {}
    for line in p.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if "=" not in s:
            continue
        k, _, v = s.partition("=")
        k = k.strip()
        if k and len(v.strip()) > 15:
            kv[k] = v.strip()
    hdr = f"# dedupe_env_fragment {p.name}\n"
    p.write_text(hdr + "\n".join(f"{k}={kv[k]}" for k in sorted(kv)) + "\n", encoding="utf-8")
    p.chmod(0o600)
    print("keys", len(kv), p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
