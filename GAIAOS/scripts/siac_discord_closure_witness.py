#!/usr/bin/env python3
"""
SIAC witness — writes evidence/discord_closure/SIAC_WITNESS.json with what actually ran.
Discord UI proof and earth-ingestor 201 lines require live mesh; this file states BLOCKED + stderr when absent.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def _run(cmd: list[str], cwd: Path, timeout: float = 300) -> tuple[int, str]:
    try:
        p = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        out = (p.stdout or "") + ("\n" + p.stderr if p.stderr else "")
        return p.returncode, out[-24000:]
    except Exception as e:
        return 99, str(e)


def _curl_code(url: str, headers: dict[str, str] | None = None) -> tuple[str, str]:
    try:
        import urllib.request

        req = urllib.request.Request(url, headers=headers or {})
        with urllib.request.urlopen(req, timeout=8) as r:
            return str(getattr(r, "status", 200) or 200), (r.read(800) or b"").decode("utf-8", "replace")
    except Exception as e:
        return f"BLOCKED:{type(e).__name__}", str(e)[:400]


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    ev_dir = repo / "evidence" / "discord_closure"
    ev_dir.mkdir(parents=True, exist_ok=True)
    out_path = ev_dir / "SIAC_WITNESS.json"

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    witness: dict = {
        "schema": "siac_witness_v1",
        "generated_at_utc": ts,
        "repo_root": str(repo),
        "honest_note": (
            "This file is substrate for Cursor/humans. "
            "Discord channel list proof = run /gaia-topology in guild + screenshot, or compare channel IDs via API. "
            "Earth-ingestor 201 = docker logs gaiaftcl-earth-ingestor on a cell after NATS feed + GAIAFTCL_INTERNAL_KEY."
        ),
        "steps": {},
    }

    forest_sh = repo / "scripts" / "test_discord_forest_all_domains.sh"
    if forest_sh.is_file():
        ec, log = _run(["bash", str(forest_sh)], cwd=repo)
        witness["steps"]["test_discord_forest_all_domains"] = {
            "exit_code": ec,
            "calorie_or_cure": ec == 0,
            "log_tail": log[-12000:],
        }
    else:
        witness["steps"]["test_discord_forest_all_domains"] = {"BLOCKED": "script missing"}

    df = repo / "services" / "discord_frontier"
    sys.path.insert(0, str(df))
    try:
        from shared.guild_topology import load_planned_channels

        planned = load_planned_channels()
        witness["steps"]["guild_topology_plan"] = {
            "channel_count": len(planned),
            "sample": [f"{p.category_display}/{p.channel_name}" for p in planned[:12]],
        }
    except Exception as e:
        witness["steps"]["guild_topology_plan"] = {"BLOCKED": str(e)}

    gw = os.environ.get("GAIAFTCL_GATEWAY_URL", "http://127.0.0.1:8803").rstrip("/")
    h = {}
    ik = os.environ.get("GAIAFTCL_INTERNAL_KEY", "").strip()
    if ik:
        h["X-Gaiaftcl-Internal-Key"] = ik
    code, body = _curl_code(f"{gw}/health", h if h else None)
    witness["steps"]["gateway_health_probe"] = {
        "url": f"{gw}/health",
        "status": code,
        "body_preview": body[:500],
    }

    code2, _ = _curl_code(f"{gw}/vqbit/torsion", h if h else None)
    witness["steps"]["gateway_torsion_probe"] = {"url": f"{gw}/vqbit/torsion", "status": code2}

    # Optional: local docker logs (no false green if container missing)
    docker_logs = ""
    try:
        p = subprocess.run(
            ["docker", "logs", "gaiaftcl-earth-ingestor", "--tail", "80"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        docker_logs = (p.stdout or "") + (p.stderr or "")
        hits = [ln for ln in docker_logs.splitlines() if "201" in ln or "vie/ingest" in ln.lower()][-20:]
        witness["steps"]["earth_ingestor_docker_logs"] = {
            "exit_code": p.returncode,
            "relevant_lines": hits,
            "raw_tail": docker_logs[-6000:],
        }
    except FileNotFoundError:
        witness["steps"]["earth_ingestor_docker_logs"] = {"BLOCKED": "docker CLI not found"}
    except Exception as e:
        witness["steps"]["earth_ingestor_docker_logs"] = {"BLOCKED": str(e)}

    witness["steps"]["discord_surface_evidence"] = {
        "BLOCKED": (
            "Not observable from repo alone. After deploy: run /gaia-topology, "
            "set DISCORD_RECEIPTS_CHANNEL_ID to #receipt-wall, confirm mesh-health posts when torsion≠NOHARM."
        )
    }

    out_path.write_text(json.dumps(witness, indent=2), encoding="utf-8")
    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
