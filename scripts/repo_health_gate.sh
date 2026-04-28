#!/usr/bin/env zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> repo health gate"

dup_projects="$(rg -n "GaiaFTCLConsole [2-9]\\.xcodeproj" GAIAOS cells --glob "*/project.pbxproj" || true)"
if [[ -n "$dup_projects" ]]; then
  echo "REFUSED: duplicate GaiaFTCLConsole project variants detected"
  echo "$dup_projects"
  exit 2
fi

tracked_runtime="$(git ls-files "runtime/sprout-cells/**" "runtime/local-run/**" "evidence/runs/**")"
if [[ -n "$tracked_runtime" ]]; then
  echo "REFUSED: generated runtime evidence is tracked:"
  echo "$tracked_runtime"
  exit 2
fi

echo "PASS: no duplicate console project variants and no tracked runtime drift"
