#!/usr/bin/env python3
"""
Long-running helper: replay failed universal_ingest JSON from MAIL_ADAPTER_QUEUE_DIR;
optionally process *.eml dropped into MAIL_DROP_DIR (e.g. host-mounted Postfix maildrop).
"""

from __future__ import annotations

import glob
import json
import os
import subprocess
import sys
import time
from pathlib import Path

QUEUE = os.environ.get("MAIL_ADAPTER_QUEUE_DIR", "/tmp/gaiaftcl-mail-inbound-queue")
DROP = os.environ.get("MAIL_DROP_DIR", "").strip()
SCAN_INTERVAL = float(os.environ.get("MAIL_ADAPTER_SCAN_INTERVAL_S", "10"))
ADAPTER = Path(__file__).resolve().parent / "adapter.py"


def _log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _replay_one(path: str) -> None:
    try:
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
        body = rec.get("claim_body")
        if not isinstance(body, dict):
            _log(f"skip bad queue record (no claim_body): {path}")
            return
        import urllib.error
        import urllib.request

        gateway = os.environ.get("GAIAFTCL_GATEWAY", "http://gaiaftcl-wallet-gate:8803").rstrip("/")
        url = f"{gateway}/universal_ingest"
        data = json.dumps(body).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        ik = os.environ.get("GAIAFTCL_INTERNAL_SERVICE_KEY", "").strip()
        if ik:
            headers["X-Gaiaftcl-Internal-Key"] = ik
        req = urllib.request.Request(url, data=data, method="POST", headers=headers)
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8")
            out = json.loads(raw) if raw.strip() else {}
        if isinstance(out, dict) and out.get("accepted") is False:
            _log(f"replay still rejected: {path} {out}")
            return
        os.unlink(path)
        _log(f"replay ok removed {path}")
    except Exception as e:
        _log(f"replay failed {path}: {e}")


def main() -> None:
    os.makedirs(QUEUE, mode=0o700, exist_ok=True)
    _log(f"drain_loop queue={QUEUE} drop={DROP or '(none)'} scan={SCAN_INTERVAL}s")
    while True:
        for p in sorted(glob.glob(os.path.join(QUEUE, "*.json"))):
            _replay_one(p)
        if DROP and os.path.isdir(DROP):
            for eml in sorted(glob.glob(os.path.join(DROP, "*.eml"))):
                try:
                    subprocess.run(
                        [sys.executable, str(ADAPTER), eml],
                        check=False,
                        timeout=300,
                    )
                except Exception as e:
                    _log(f"adapter eml failed {eml}: {e}")
        time.sleep(SCAN_INTERVAL)


if __name__ == "__main__":
    main()
