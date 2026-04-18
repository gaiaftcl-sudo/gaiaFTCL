#!/usr/bin/env python3
"""Merge overlay KEY=value into base env file; overlay wins. Preserves base keys not in overlay."""
from __future__ import annotations

import pathlib
import sys


def parse(p: pathlib.Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not p.is_file():
        return out
    for line in p.read_text(encoding="utf-8").splitlines():
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


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: merge_env_overlay.py <base.env> <overlay.env> <out.env>", file=sys.stderr)
        return 1
    base = parse(pathlib.Path(sys.argv[1]))
    over = parse(pathlib.Path(sys.argv[2]))
    merged = dict(base)
    merged.update(over)
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
    lines: list[str] = ["# merge_env_overlay — do not commit", ""]
    for k in preferred:
        if k in merged:
            lines.append(f"{k}={merged[k]}")
            seen.add(k)
    for k in sorted(merged.keys()):
        if k in seen:
            continue
        lines.append(f"{k}={merged[k]}")
    outp = pathlib.Path(sys.argv[3])
    outp.parent.mkdir(parents=True, exist_ok=True)
    outp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    outp.chmod(0o600)
    print("wrote", outp, "keys", len(merged))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
