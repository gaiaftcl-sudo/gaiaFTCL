#!/usr/bin/env python3
"""Canonical native Fusion sub-invariant caller.

Runs the Python-native invariant pass (run_native_rust_fusion_invariant.py) with
strict local defaults and emits a release-scoped latest receipt so the full release
invariant can treat this as the canonical sub-governor.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _run_cmd(
    cmd: list[str],
    cwd: Path,
    env: dict[str, str],
    timeout: int | None = None,
) -> tuple[int, str]:
    cp = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        text=True,
        check=False,
    )
    return cp.returncode, cp.stdout


def _copy_latest_receipt(repo: Path) -> tuple[dict[str, Any], Path] | tuple[None, None]:
    native_latest = repo / "evidence" / "native_fusion" / "LATEST_NATIVE_RUST_FUSION_RESULT.json"
    if not native_latest.is_file():
        candidates = sorted((repo / "evidence" / "native_fusion").glob("NATIVE_RUST_FUSION_INVARIANT_*.json"))
        if candidates:
            native_latest = max(candidates, key=lambda p: p.name)
    if not native_latest.is_file():
        return None, native_latest
    try:
        payload = json.loads(native_latest.read_text(encoding="utf-8"))
        return payload, native_latest
    except (OSError, json.JSONDecodeError):
        return None, native_latest


def _write_release_latest(
    repo: Path,
    native_payload: dict[str, Any] | None,
    native_latest: Path,
    stdout_tail: str,
    script_path: Path,
) -> Path:
    evidence_release = repo / "evidence" / "release"
    evidence_release.mkdir(parents=True, exist_ok=True)

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    if native_payload is None:
        receipt: dict[str, Any] = {
            "schema": "gaiaftcl_native_fusion_sub_invariant_bridge_v1",
            "terminal": "PARTIAL",
            "run_id": f"bridge_{ts}",
            "ts_utc": _now_utc_iso(),
            "native_receipt_path": str(native_latest),
            "subscript": str(script_path),
            "sub_exit": 1,
            "sub_output_tail": stdout_tail[-6000:],
        }
    else:
        receipt = dict(native_payload)
        receipt.setdefault("schema", "gaiaftcl_native_fusion_sub_invariant_bridge_v1")
        receipt.setdefault("terminal", native_payload.get("terminal", "PARTIAL"))
        receipt.setdefault("subscript", str(script_path))
        receipt["native_receipt_path"] = str(native_latest)
        receipt["sub_output_tail"] = stdout_tail[-6000:]

    latest = evidence_release / "MAC_FUSION_SUB_INVARIANT_latest.json"
    latest.write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    stamped = evidence_release / f"MAC_FUSION_SUB_INVARIANT_{ts}.json"
    stamped.write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    return latest


def _set_default_env() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("C4_INVARIANT_MESH_NINE_CELL_OFFLINE", "1")
    env.setdefault("GAIAFTCL_INVARIANT_MESH_HEAL", "0")
    env.setdefault("GAIAFTCL_INVARIANT_NO_FUSION_UI_BOOTSTRAP", "0")
    # Bootstrap behavior is explicit and bounded for live proofing.
    # Bootstrap the native Fusion UI by default unless explicitly disabled by the caller.
    # When GAIAFTCL_INVARIANT_NO_FUSION_UI_BOOTSTRAP=1, bootstrap is skipped.
    env.setdefault("GAIAFTCL_INVARIANT_FUSION_UI_BOOTSTRAP_SEC", "20")
    env.setdefault("GAIAFTCL_INVARIANT_FUSION_UI_COMPILE_GRACE_SEC", "20")
    env.setdefault("GAIAFTCL_INVARIANT_FUSION_UI_BOOTSTRAP_ATTEMPTS", "1")
    env.setdefault("GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_MAX", "1")
    env.setdefault("GAIAFTCL_INVARIANT_APP_SELF_HEAL", "1")
    env.setdefault("GAIAFTCL_INVARIANT_APP_HEALTH_RETRIES", "6")
    env.setdefault("GAIAFTCL_INVARIANT_GATE_RETRY_MAX", "3")
    env.setdefault("GAIAFTCL_INVARIANT_BUILD_GATE_RETRIES", "3")
    return env


def _build_release_line(receipt: dict[str, Any], rc: int) -> str:
    terminal = str(receipt.get("terminal") or "") if receipt else "PARTIAL"
    return "CURE" if rc == 0 and terminal == "CURE" else terminal or "PARTIAL"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run canonical native Fusion macOS invariant")
    parser.add_argument("--repo-root", default=str(Path.cwd()), help="Repository root")
    parser.add_argument(
        "--max-cycles",
        type=int,
        default=1,
        help="GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_MAX (0 = unlimited)",
    )
    parser.add_argument(
        "--bootstrap",
        action="store_true",
        help="Allow invariant-managed bootstrap (currently on by default)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=None,
        help="Subprocess timeout seconds (optional)",
    )
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve()
    script_path = Path(__file__).resolve()
    native_script = repo / "scripts" / "run_native_rust_fusion_invariant.py"

    if not native_script.is_file():
        print(f"MISSING native invariant script: {native_script}", file=sys.stderr)
        return 1

    env = _set_default_env()
    env["GAIAFTCL_INVARIANT_OUTER_FIX_LOOP_MAX"] = str(args.max_cycles)

    cp_start = time.perf_counter()
    rc, output = _run_cmd([sys.executable, str(native_script)], cwd=repo, env=env, timeout=args.timeout)
    cp_elapsed = time.perf_counter() - cp_start

    native_payload, native_latest = _copy_latest_receipt(repo)
    release_latest = _write_release_latest(repo, native_payload, native_latest, output, script_path)

    terminal = _build_release_line(native_payload if isinstance(native_payload, dict) else {}, rc)

    if isinstance(native_payload, dict):
        run_id = native_payload.get("run_id", "unknown")
        print(f"SUB_GAIA run_id={run_id}")
        print(f"STATE: {terminal}")
        print(f"Run time: {cp_elapsed:.2f}s")
        print(f"Native receipt: {native_latest}")
        print(f"Release latest: {release_latest}")
        if terminal != "CURE":
            print(f"Failed gate: {native_payload.get('failed_gate')}")
    else:
        print(f"STATE: PARTIAL (no native receipt parse)")
        print(f"Run time: {cp_elapsed:.2f}s")
        print(f"Native stdout tail: {output[-4000:]}")
        print(f"Release latest: {release_latest}")

    # Keep artifact for full release governor and operator inspection.
    return 0 if terminal == "CURE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
