#!/usr/bin/env zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$REPO_ROOT/cells/xcode/GaiaComposite.xcworkspace"
FRANKLIN_DIR="$REPO_ROOT/GAIAOS/macos/Franklin"

if [[ ! -d "$WORKSPACE" ]]; then
  echo "REFUSED: composite workspace missing: $WORKSPACE" >&2
  exit 2
fi

if [[ ! -f "$FRANKLIN_DIR/Package.swift" ]]; then
  echo "REFUSED: Franklin Package.swift missing" >&2
  exit 2
fi

echo "==> validating Franklin package tests"
swift test --package-path "$FRANKLIN_DIR"

echo "==> running canonical Franklin programming step"
"$REPO_ROOT/scripts/program_franklin_app.zsh"

echo "==> opening composite workspace"
open "$WORKSPACE"

echo "PASS: composite workspace opened and Franklin programming completed"
