#!/usr/bin/env python3
"""Validate native plant adapter hot swap witness."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    adapters_path = root / "spec" / "native_fusion" / "plant_adapters.json"
    witness_path = root / "evidence" / "native_fusion" / "plant_hot_swap_witness.json"
    out_path = root / "evidence" / "native_fusion" / "plant_hot_swap_validation.json"
    adapters = json.loads(adapters_path.read_text(encoding="utf-8"))
    witness = json.loads(witness_path.read_text(encoding="utf-8"))
    kinds = adapters.get("kinds", [])
    from_kind = witness.get("from_kind")
    to_kind = witness.get("to_kind")
    ok = (
        witness.get("terminal") == "CALORIE"
        and isinstance(kinds, list)
        and from_kind in kinds
        and to_kind in kinds
        and from_kind != to_kind
    )
    out = {
        "schema": "gaiaftcl_plant_hot_swap_validation_v1",
        "terminal": "CALORIE" if ok else "REFUSED",
        "from_kind": from_kind,
        "to_kind": to_kind,
        "adapter_kinds": kinds,
        "ts_utc": datetime.now(timezone.utc).isoformat(),
    }
    out_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(out_path)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
