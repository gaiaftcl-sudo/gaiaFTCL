#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "GaiaFTCL native invariant (default path)"
echo "Legacy sidecar invariant remains at scripts/run_mac_fusion_sub_invariant.py"
python3 scripts/run_native_rust_fusion_invariant.py "$@"
