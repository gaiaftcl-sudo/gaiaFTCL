#!/usr/bin/env python3
"""
Gym-TORAX metrics: append episode JSONL when operator supplies real episode output (no synthetic plasma).

Set TORAX_FEEDER_READY=1 and TORAX_RUN_CMD to a shell command that prints one JSON object per line
with delta_h or delta_H (float). Lines are written to TORAX_METRICS_JSONL_OUT (default evidence path).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    root = Path(os.environ.get("GAIA_ROOT", ".")).resolve()
    ev = root / "evidence" / "fusion_control"
    ev.mkdir(parents=True, exist_ok=True)
    out = Path(
        os.environ.get(
            "TORAX_METRICS_JSONL_OUT",
            str(ev / "torax_episode_metrics.jsonl"),
        )
    )
    cmd = os.environ.get("TORAX_RUN_CMD", "").strip()
    ready = os.environ.get("TORAX_FEEDER_READY") == "1"

    if ready and cmd:
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stderr or proc.stdout or "TORAX_RUN_CMD failed\n")
            return proc.returncode
        with out.open("a", encoding="utf-8") as f:
            for line in proc.stdout.splitlines():
                line = line.strip()
                if not line:
                    continue
                obj = json.loads(line)
                if "delta_h" not in obj and "delta_H" not in obj:
                    sys.stderr.write(
                        "REFUSED: each stdout line must be JSON with delta_h or delta_H\n"
                    )
                    return 2
                rec = {"schema": "torax_episode_metric_v1", **obj}
                f.write(json.dumps(rec, separators=(",", ":")) + "\n")
        print(f"CALORIE: appended episode metrics to {out}")
        return 0

    sys.stderr.write(
        "BLOCKED: set TORAX_FEEDER_READY=1 and TORAX_RUN_CMD to your JAX/TORAX episode emitter.\n"
        "S4 surface: deploy/fusion_mesh/config/benchmarks/gym_torax_v1.json\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
