#!/usr/bin/env zsh
# OQ — full GaiaFusion unit/UI test run on arm64 macOS (same posture as Mac Cell CI).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
export GAIAFUSION_MOORING_TIMEOUT_SECONDS="${GAIAFUSION_MOORING_TIMEOUT_SECONDS:-10}"

cd "$ROOT"
xcodebuild test \
  -scheme GaiaFusion \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED"

echo "run_oq_validation: OK"
