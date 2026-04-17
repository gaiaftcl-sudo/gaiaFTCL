#!/usr/bin/env python3
"""
Chess Move 3 remediation: publish minimal JSON to NATS subjects that satisfy
earth_pattern_matches() in services/discord_frontier/shared/cell_base.py so Owl
/cell earth_feed_health timestamps advance (Scout re-ingest signal).
Requires network path to NATS (tunnel or local). No simulated success: exits non-zero on failure.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import shutil
import subprocess
import sys


def _concrete_subject_for_pattern(pat: str) -> str:
    p = pat.strip()
    if not p:
        return ""
    if p.endswith(".>"):
        base = p[:-2]
        return f"{base}.chess_scout_poke"
    if p.endswith(".*"):
        base = p[:-2]
        return f"{base}.chess_scout_poke"
    return p


def _publish_nats_cli(url: str, subj: str, payload: str) -> tuple[bool, str]:
    exe = shutil.which("nats")
    if not exe:
        return False, "nats CLI not on PATH"
    r = subprocess.run(
        [exe, "pub", "-s", url, subj, payload],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if r.returncode != 0:
        return False, (r.stderr or r.stdout or "nats pub failed")[:400]
    return True, "ok (nats CLI)"


async def _publish_one(url: str, pattern: str) -> tuple[str, bool, str]:
    subj = _concrete_subject_for_pattern(pattern)
    if not subj:
        return pattern, False, "empty pattern"
    payload = json.dumps(
        {
            "scout": "chess_8d_remediate",
            "pattern": pattern,
            "subject": subj,
        }
    )
    try:
        import nats  # type: ignore

        nc = await nats.connect(url)
        try:
            await nc.publish(subj, payload.encode("utf-8"))
        finally:
            await nc.drain()
        return subj, True, "ok (nats-py)"
    except Exception as e:
        ok, msg = await asyncio.to_thread(_publish_nats_cli, url, subj, payload)
        if ok:
            return subj, True, msg
        return subj, False, f"nats-py: {e}; cli: {msg}"


async def _run(url: str, patterns: list[str]) -> int:
    failed = 0
    for pat in patterns:
        subj, ok, msg = await _publish_one(url, pat)
        line = f"{'OK' if ok else 'FAIL'} {pat} -> {subj} ({msg})"
        print(line)
        if not ok:
            failed += 1
    return 0 if failed == 0 else 2


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--nats-url",
        default=os.environ.get("NATS_URL", "nats://127.0.0.1:4222"),
        help="NATS server URL (default NATS_URL or nats://127.0.0.1:4222)",
    )
    ap.add_argument(
        "--patterns",
        default="",
        help="Comma-separated earth subject patterns (same strings as cell_base earth_subjects)",
    )
    ap.add_argument("--patterns-file", type=argparse.FileType("r"), help="One pattern per line")
    args = ap.parse_args()
    raw = [x.strip() for x in args.patterns.split(",") if x.strip()]
    if args.patterns_file:
        raw.extend(
            ln.strip()
            for ln in args.patterns_file
            if ln.strip() and not ln.strip().startswith("#")
        )
    if not raw:
        print("WARN: no patterns to poke — nothing to do", file=sys.stderr)
        return 0
    return asyncio.run(_run(args.nats_url, raw))


if __name__ == "__main__":
    raise SystemExit(main())
