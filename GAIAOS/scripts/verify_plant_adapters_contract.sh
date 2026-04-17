#!/usr/bin/env bash
# GF-REQ-SWAP-001: validate spec/native_fusion/plant_adapters.json schema and kinds (no drift vs PlantKindsCatalog).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
JSON_PATH="${1:-spec/native_fusion/plant_adapters.json}"
exec python3 - "$JSON_PATH" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
canonical = {
    "tokamak", "stellarator", "frc", "spheromak", "mirror", "inertial",
    "spherical_tokamak", "z_pinch", "mif",
}
raw = path.read_text(encoding="utf-8")
obj = json.loads(raw)
assert obj.get("schema") == "gaiaftcl_native_fusion_plant_adapters_v1", "schema mismatch"
kinds = obj.get("kinds") or []
assert isinstance(kinds, list) and len(kinds) > 0, "kinds empty"
bad = [k for k in kinds if k not in canonical]
assert not bad, f"unknown kinds (not in canonical set): {bad}"
caps = obj.get("required_capabilities") or []
assert len(caps) >= 3, "required_capabilities too thin"
print(f"CALORIE: plant_adapters OK — {path} kinds={len(kinds)}")
sys.exit(0)
PY
