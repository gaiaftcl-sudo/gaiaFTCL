#!/usr/bin/env bash
# Stop fusion_cell_long_run_runner.sh (stop file on next loop iteration).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOP="$ROOT/evidence/fusion_control/LONG_RUN_STOP"
mkdir -p "$(dirname "$STOP")"
touch "$STOP"
echo "Long-run stop requested: $STOP"
