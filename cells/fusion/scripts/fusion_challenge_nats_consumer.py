#!/usr/bin/env python3
"""
Subscribe to gaiaftcl.fusion.challenge.ledger (or FUSION_CHALLENGE_NATS_SUBJECT), POST each JSON payload
to Next /api/fusion/challenge-ledger (same ops as CLI).

Requires: pip install nats-py
Env:
  NATS_URL                 default nats://127.0.0.1:4222
  FUSION_LEDGER_API_URL    default http://127.0.0.1:8910
  FUSION_CHALLENGE_LEDGER_SECRET  required
  FUSION_CHALLENGE_NATS_SUBJECT   default gaiaftcl.fusion.challenge.ledger
"""
from __future__ import annotations

import asyncio
import json
import os
import urllib.error
import urllib.request

try:
    import nats  # type: ignore
except ImportError:
    raise SystemExit("REFUSED: pip install nats-py")


def post_ledger(payload: dict) -> None:
    secret = os.environ.get("FUSION_CHALLENGE_LEDGER_SECRET", "").strip()
    if not secret:
        raise RuntimeError("FUSION_CHALLENGE_LEDGER_SECRET required")
    base = os.environ.get("FUSION_LEDGER_API_URL", "http://127.0.0.1:8910").rstrip("/")
    url = f"{base}/api/fusion/challenge-ledger"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "x-fusion-challenge-ledger-secret": secret,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read().decode("utf-8", errors="replace")
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status}: {body[:500]}")


async def main() -> None:
    subj = os.environ.get("FUSION_CHALLENGE_NATS_SUBJECT", "gaiaftcl.fusion.challenge.ledger").strip()
    nurl = os.environ.get("NATS_URL", "nats://127.0.0.1:4222").strip()
    nc = await nats.connect(nurl)

    async def handler(msg) -> None:
        try:
            payload = json.loads(msg.data.decode("utf-8"))
            await asyncio.to_thread(post_ledger, payload)
            print("CALORIE posted op", payload.get("op"), payload.get("team_id", ""))
        except (json.JSONDecodeError, urllib.error.URLError, RuntimeError, OSError) as e:
            print("REFUSED", e)

    await nc.subscribe(subj, cb=handler)
    print(f"CALORIE fusion challenge NATS → ledger subscribed {subj} @ {nurl}")
    while True:
        await asyncio.sleep(3600)


if __name__ == "__main__":
    asyncio.run(main())
