#!/usr/bin/env python3
"""
Emit Gym-TORAX-shaped JSON lines to stdout for feed_torax.py.

Source of truth: Metal batch lines already in evidence/fusion_control/long_run_signals.jsonl
(worst_max_abs_error → delta_h). This is a **substrate bridge** until a real JAX/TORAX episode
runner is wired; values are not simulated — they are read from the logged receipts.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def is_metal_receipt(o: dict) -> bool:
    if o.get("schema") == "fusion_control_batch_receipt_v1":
        return True
    eng = o.get("validation_engine")
    if eng in ("gpu_fused_multicycle", "per_cycle_gpu_sync"):
        w = o.get("wall_time_ms")
        return isinstance(w, (int, float)) or isinstance(w, str)
    return False


def tail_text_lines(path: Path, max_lines: int = 8000) -> list[str]:
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    lines = [ln.strip() for ln in raw.splitlines() if ln.strip()]
    return lines[-max_lines:]


def main() -> int:
    root = Path(os.environ.get("GAIA_ROOT", ".")).resolve()
    default_jsonl = root / "evidence" / "fusion_control" / "long_run_signals.jsonl"
    path = Path(os.environ.get("TORAX_SIGNALS_JSONL", str(default_jsonl))).resolve()

    if not path.is_file():
        sys.stderr.write(f"REFUSED: missing signals JSONL: {path}\n")
        return 2

    metal: list[dict] = []
    for line in tail_text_lines(path):
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(o, dict):
            continue
        if o.get("control_signal") == "fusion_cell_batch" and is_metal_receipt(o):
            metal.append(o)
        elif is_metal_receipt(o):
            metal.append(o)

    out_rows: list[tuple[int, float]] = []
    for i, o in enumerate(metal):
        dh = o.get("worst_max_abs_error")
        try:
            f = float(dh)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            continue
        if not (f == f):  # NaN
            continue
        ep = o.get("episode")
        idx = int(ep) if isinstance(ep, int) else i
        out_rows.append((idx, f))

    if not out_rows:
        sys.stderr.write(
            "REFUSED: no Metal batch lines with numeric worst_max_abs_error in tail — "
            "run NSTX-U soak or long-run first.\n"
        )
        return 2

    for idx, f in out_rows:
        print(json.dumps({"episode": idx, "delta_h": f}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
