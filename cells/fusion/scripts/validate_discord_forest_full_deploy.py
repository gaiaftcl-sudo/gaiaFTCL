#!/usr/bin/env python3
"""
Exit 0 only if every required DISCORD_* substitution in forest + domains compose
has a non-empty value in discord-forest.env.

Optional (may be empty): role/channel/path-style vars listed in OPTIONAL_DISCORD_KEYS.

Usage:
  python3 scripts/validate_discord_forest_full_deploy.py \\
    --repo-root /opt/gaia/GAIAOS \\
    --env-file /etc/gaiaftcl/discord-forest.env
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

# May be unset for a minimal boot (compose allows :- defaults).
OPTIONAL_DISCORD_KEYS: frozenset[str] = frozenset(
    {
        "DISCORD_FOREST_ENV_FILE",
        "DISCORD_APP_CELL_ID",
        "DISCORD_MOORED_ROLE_ID",
        "DISCORD_QUARANTINE_ROLE_ID",
        "DISCORD_INCEPTION_AUDIT_CHANNEL_ID",
        "DISCORD_RECEIPTS_CHANNEL_ID",
    }
)

COMPOSE_FILES: tuple[str, ...] = (
    "docker-compose.discord-forest.yml",
    "docker-compose.discord-domains.yml",
)


def _parse_env_file(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if "=" not in s:
            continue
        k, _, v = s.partition("=")
        k = k.strip()
        if k:
            out[k] = v.strip()
    return out


def _required_discord_keys(compose_dir: pathlib.Path) -> set[str]:
    keys: set[str] = set()
    ref = re.compile(r"\$\{(DISCORD_[A-Z0-9_]+)")
    for name in COMPOSE_FILES:
        p = compose_dir / name
        if not p.is_file():
            print("REFUSED: missing", p, file=sys.stderr)
            raise SystemExit(1)
        text = p.read_text(encoding="utf-8", errors="replace")
        for m in ref.finditer(text):
            keys.add(m.group(1))
    keys -= OPTIONAL_DISCORD_KEYS
    return keys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", type=pathlib.Path, required=True)
    ap.add_argument("--env-file", type=pathlib.Path, required=True)
    args = ap.parse_args()

    compose_dir = args.repo_root / "services" / "discord_frontier"
    if not compose_dir.is_dir():
        print("REFUSED: missing", compose_dir, file=sys.stderr)
        return 1
    if not args.env_file.is_file():
        print("REFUSED: missing", args.env_file, file=sys.stderr)
        return 1

    required = _required_discord_keys(compose_dir)
    env = _parse_env_file(args.env_file.read_text(encoding="utf-8"))
    missing = sorted(k for k in required if not (env.get(k) or "").strip())
    if missing:
        print("REFUSED: empty or missing keys (fill discord-forest.env):", file=sys.stderr)
        for k in missing:
            print(" ", k, file=sys.stderr)
        return 1
    print("ok", len(required), "required DISCORD_* keys set", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
