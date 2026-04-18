#!/usr/bin/env python3
"""
Merge discord-forest.env: keep existing values; add missing keys from .env.example defaults
and from compose-referenced DISCORD_* variables (empty value if absent).

Does not print secret values. Intended for /etc/gaiaftcl/discord-forest.env on the head.

Usage:
  python3 scripts/merge_discord_forest_env.py \\
    --repo-root /opt/gaia/GAIAOS \\
    --current /etc/gaiaftcl/discord-forest.env \\
    --out /etc/gaiaftcl/discord-forest.env.new

Optional:
  --secrets /etc/gaiaftcl/secrets.env   (upsert DISCORD_GUILD_ID if missing in current)
  --set ARANGO_DB=gaiaftcl              (repeatable)
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys


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


COMPOSE_FILES: tuple[str, ...] = (
    "docker-compose.discord-forest.yml",
    "docker-compose.discord-domains.yml",
)


def _compose_discord_keys(compose_dir: pathlib.Path) -> set[str]:
    keys: set[str] = set()
    ref = re.compile(r"\$\{(DISCORD_[A-Z0-9_]+)")
    for name in COMPOSE_FILES:
        p = compose_dir / name
        if not p.is_file():
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        for m in ref.finditer(text):
            keys.add(m.group(1))
    return keys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", type=pathlib.Path, required=True)
    ap.add_argument("--current", type=pathlib.Path, default=pathlib.Path("/etc/gaiaftcl/discord-forest.env"))
    ap.add_argument("--out", type=pathlib.Path, required=True)
    ap.add_argument("--secrets", type=pathlib.Path, default=None)
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VAL", help="force set (repeatable)")
    args = ap.parse_args()

    example = args.repo_root / "services" / "discord_frontier" / ".env.example"
    if not example.is_file():
        print("REFUSED: missing", example, file=sys.stderr)
        return 1

    compose_dir = args.repo_root / "services" / "discord_frontier"
    if not compose_dir.is_dir():
        print("REFUSED: missing", compose_dir, file=sys.stderr)
        return 1

    base = _parse_env_file(example.read_text(encoding="utf-8"))
    current = _parse_env_file(args.current.read_text(encoding="utf-8")) if args.current.is_file() else {}

    merged: dict[str, str] = dict(base)
    merged.update(current)

    for k in sorted(_compose_discord_keys(compose_dir)):
        merged.setdefault(k, "")

    if args.secrets and args.secrets.is_file():
        sec = _parse_env_file(args.secrets.read_text(encoding="utf-8"))
        gid = (sec.get("DISCORD_GUILD_ID") or "").strip()
        if gid and not (merged.get("DISCORD_GUILD_ID") or "").strip():
            merged["DISCORD_GUILD_ID"] = gid
        isk = (sec.get("GAIAFTCL_INTERNAL_SERVICE_KEY") or "").strip()
        if isk and not (merged.get("GAIAFTCL_INTERNAL_SERVICE_KEY") or "").strip():
            merged["GAIAFTCL_INTERNAL_SERVICE_KEY"] = isk
        cur_app = (merged.get("DISCORD_APP_BOT_TOKEN") or "").strip()
        if not cur_app:
            for k in ("DISCORD_APP_BOT_TOKEN", "DISCORD_BOT_TOKEN", "DISCORD_MEMBRANE_TOKEN"):
                v = (sec.get(k) or "").strip()
                if v:
                    merged["DISCORD_APP_BOT_TOKEN"] = v
                    break

    for item in args.set:
        if "=" not in item:
            print("REFUSED: bad --set", item, file=sys.stderr)
            return 1
        k, _, v = item.partition("=")
        merged[k.strip()] = v.strip()

    # Stable output order: known prefix keys first, then rest alpha
    preferred = [
        "NATS_URL",
        "ARANGO_URL",
        "ARANGO_DB",
        "ARANGO_USER",
        "ARANGO_PASSWORD",
        "DISCORD_GUILD_ID",
        "MESH_PEER_REGISTRY_URL",
        "GAIAFTCL_GATEWAY_URL",
        "GAIAFTCL_INTERNAL_SERVICE_KEY",
    ]
    seen: set[str] = set()
    lines: list[str] = [
        "# Merged by merge_discord_forest_env.py — do not commit. chmod 600.",
        "# Set each DISCORD_BOT_TOKEN_* in Developer Portal (Bot → Reset Token / copy).",
        "",
    ]
    for k in preferred:
        if k in merged:
            lines.append(f"{k}={merged[k]}")
            seen.add(k)
    for k in sorted(merged.keys()):
        if k in seen:
            continue
        lines.append(f"{k}={merged[k]}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", args.out, "keys", len(merged), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
