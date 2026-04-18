"""
Nine-cell WAN mesh: probe :8803/health, optional per-cell SSH docker restart, then full deploy.

Used by ``run_native_rust_fusion_invariant.py`` — heal when possible, receipt when not.
"""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path
from typing import Any, Callable, Optional


def parse_probe_stdout(stdout: str) -> dict[str, Any]:
    ok_c = 0
    unhealthy: list[str] = []
    failed_ips: list[str] = []
    for line in stdout.splitlines():
        if not line or line.startswith("#"):
            continue
        if line.startswith("OK\t"):
            ok_c += 1
        elif line.startswith("FAIL\t"):
            parts = line.split("\t")
            if len(parts) >= 3:
                unhealthy.append(parts[1])
                failed_ips.append(parts[2])
    nine_ok = ok_c == 9 and len(unhealthy) == 0
    return {
        "healthy_count": ok_c,
        "unhealthy": unhealthy,
        "failed_ips": failed_ips,
        "nine_ok": nine_ok,
    }


def run_mesh_probe(repo_root: Path, timeout: int = 180) -> tuple[int, str, dict[str, Any]]:
    script = repo_root / "scripts" / "invariant_mesh_green_probe.sh"
    cp = subprocess.run(
        ["bash", str(script)],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    out = (cp.stdout or "") + (cp.stderr or "")
    info = parse_probe_stdout(cp.stdout or "")
    info["probe_rc"] = cp.returncode
    return cp.returncode, out, info


def _ssh_identity_args() -> list[str]:
    k = os.environ.get("GAIAFTCL_INVARIANT_MESH_SSH_KEY", "").strip()
    if k:
        p = Path(k).expanduser()
        if p.is_file():
            return ["-i", str(p)]
    for cand in (
        Path.home() / ".ssh" / "qfot_unified",
        Path.home() / ".ssh" / "id_ed25519",
        Path.home() / ".ssh" / "id_rsa",
    ):
        if cand.is_file():
            return ["-i", str(cand)]
    return []


def ssh_restart_gateway(ip: str, timeout: int = 120) -> tuple[int, str]:
    ident = _ssh_identity_args()
    if not ident:
        return 125, "no_ssh_identity_for_mesh_heal"
    remote = (
        "docker restart fot-mcp-gateway-mesh 2>/dev/null || "
        "(test -d /opt/gaia/GAIAOS && cd /opt/gaia/GAIAOS && "
        "docker compose -f docker-compose.cell.yml restart fot-mcp-gateway-mesh) 2>/dev/null || true"
    )
    cmd = [
        "ssh",
        *ident,
        "-o",
        "ConnectTimeout=15",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        f"root@{ip}",
        remote,
    ]
    cp = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
    tail = ((cp.stderr or "") + (cp.stdout or ""))[-2000:]
    return cp.returncode, tail


def probe_and_heal_until_healthy(
    repo_root: Path,
    *,
    max_heal_rounds: int,
    heal_wait_sec: float,
    post_deploy_sleep: float,
    deploy_script: Path,
    deploy_timeout: int,
    dmg_script: Optional[Path],
    push_dmg: bool,
    on_event: Optional[Callable[[dict[str, Any]], None]] = None,
) -> tuple[bool, dict[str, Any]]:
    """
    Probe → for each failed cell SSH restart gateway container → re-probe → full deploy + sleep → repeat.
    """
    rounds_log: list[dict[str, Any]] = []
    last_info: dict[str, Any] = {}

    for round_i in range(1, max_heal_rounds + 1):
        rc, _out, info = run_mesh_probe(repo_root)
        last_info = info
        entry: dict[str, Any] = {
            "round": round_i,
            "phase": "probe",
            "probe_rc": rc,
            "healthy_count": info["healthy_count"],
            "unhealthy": list(info["unhealthy"]),
        }
        rounds_log.append(entry)
        if on_event:
            on_event(
                {
                    "mesh_round": round_i,
                    "nine_ok": info["nine_ok"],
                    "healthy_count": info["healthy_count"],
                    "unhealthy": info["unhealthy"],
                }
            )

        if info["nine_ok"]:
            return True, {
                "mesh_green": True,
                "heal_rounds": rounds_log,
                "final": info,
            }

        # Last probe round: no further SSH/deploy; outer gate may retry.
        if round_i == max_heal_rounds:
            break

        heals: list[dict[str, Any]] = []
        for ip in info.get("failed_ips") or []:
            hrc, htail = ssh_restart_gateway(ip)
            heals.append({"ip": ip, "rc": hrc, "tail": htail[-400:]})
        rounds_log.append({"round": round_i, "phase": "ssh_restart", "heals": heals})
        if on_event:
            on_event({"mesh_heal": "ssh_restart", "cells": len(heals)})

        time.sleep(heal_wait_sec)

        _rc2, _, info2 = run_mesh_probe(repo_root)
        last_info = info2
        rounds_log.append(
            {
                "round": round_i,
                "phase": "probe_after_ssh",
                "healthy_count": info2["healthy_count"],
                "unhealthy": list(info2["unhealthy"]),
            }
        )
        if info2["nine_ok"]:
            return True, {
                "mesh_green": True,
                "heal_rounds": rounds_log,
                "final": info2,
            }

        if deploy_script.is_file():
            dcp = subprocess.run(
                ["bash", str(deploy_script)],
                cwd=str(repo_root),
                capture_output=True,
                text=True,
                timeout=deploy_timeout,
                check=False,
            )
            d_tail = ((dcp.stderr or "") + (dcp.stdout or ""))[-800:]
            rounds_log.append(
                {
                    "round": round_i,
                    "phase": "deploy_crystal",
                    "deploy_rc": dcp.returncode,
                    "deploy_tail": d_tail,
                }
            )
            if on_event:
                on_event({"mesh_heal": "deploy_crystal", "deploy_rc": dcp.returncode})
        else:
            rounds_log.append({"round": round_i, "phase": "deploy_skipped", "reason": "missing_deploy_script"})

        if push_dmg and dmg_script is not None and dmg_script.is_file():
            dm = subprocess.run(
                ["bash", str(dmg_script)],
                cwd=str(repo_root),
                capture_output=True,
                text=True,
                timeout=deploy_timeout,
                check=False,
            )
            rounds_log.append(
                {
                    "round": round_i,
                    "phase": "dmg_push",
                    "rc": dm.returncode,
                    "tail": ((dm.stderr or "") + (dm.stdout or ""))[-500:],
                }
            )

        time.sleep(post_deploy_sleep)

    return False, {
        "mesh_green": False,
        "heal_rounds": rounds_log,
        "final": last_info,
        "reason": "nine_cell_mesh_not_green_after_heal",
    }
