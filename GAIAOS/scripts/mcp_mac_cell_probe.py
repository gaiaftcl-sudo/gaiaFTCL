#!/usr/bin/env python3
"""Probe local Mac full-cell MCP gateway (same rules as verify_gaiafusion_working_app.sh mac_cell phase).

Env:
  GAIAFUSION_MAC_CELL_HOST — default 127.0.0.1
  GAIAFUSION_MAC_CELL_PORT — default 8803

Stdout: one JSON object {"rows":[...], "fail": null | "<reason>"}
Exit code: always 0 (callers interpret JSON.fail).
"""
from __future__ import annotations

import json
import os
import subprocess


def curl_code(url: str) -> str:
    try:
        r = subprocess.run(
            ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "6", "--max-time", "14", url],
            capture_output=True,
            text=True,
            timeout=22,
        )
        return (r.stdout or "000").strip()
    except Exception:
        return "000"


def main() -> None:
    host = os.environ.get("GAIAFUSION_MAC_CELL_HOST", "127.0.0.1").strip() or "127.0.0.1"
    port_s = os.environ.get("GAIAFUSION_MAC_CELL_PORT", "8803").strip() or "8803"
    try:
        port = int(port_s)
    except ValueError:
        port = 8803
    base = f"http://{host}:{port}"
    hc = curl_code(f"{base}/health")
    cc = curl_code(f"{base}/claims?limit=1")
    rows = [{"cell": "mac_full_cell", "ip": host, "port": port, "health_http": hc, "claims_http": cc}]
    fail = None
    if not hc.isdigit() or not (200 <= int(hc) < 300):
        fail = f"health:mac_full_cell:{host}:{port}:{hc}"
    elif cc == "000" or (cc.isdigit() and cc.startswith("5")):
        fail = f"claims:mac_full_cell:{host}:{port}:{cc}"
    print(json.dumps({"rows": rows, "fail": fail}))


if __name__ == "__main__":
    main()
