#!/usr/bin/env bash
# Gate before handing /fusion-s4 to live testers: repo layout, tooling, unit tests, production build.
# Optional E2E: FUSION_PREFLIGHT_E2E=1 npm run fusion:preflight (from gaiaos_ui_web)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
UI="$ROOT/services/gaiaos_ui_web"

die() { echo "REFUSED: $*" >&2; exit 2; }

echo "[preflight_fusion_ui_live] GAIA_ROOT=$GAIA_ROOT"

if [[ -f "$ROOT/scripts/scope_fortress_scan.sh" ]]; then
  echo "[preflight_fusion_ui_live] running scope_fortress_scan.sh"
  bash "$ROOT/scripts/scope_fortress_scan.sh"
fi

[[ -f "$ROOT/deploy/fusion_mesh/fusion_projection.json" ]] ||
  die "missing deploy/fusion_mesh/fusion_projection.json"

mkdir -p "$ROOT/evidence/fusion_control"
[[ -w "$ROOT/evidence/fusion_control" ]] || die "evidence/fusion_control not writable"

command -v node >/dev/null 2>&1 || die "node not found"
command -v npm >/dev/null 2>&1 || die "npm not found"
command -v jq >/dev/null 2>&1 || die "jq not found (PCSSP injector + reports)"
command -v python3 >/dev/null 2>&1 || die "python3 not found (TORAX feeder + tooling)"

[[ -d "$UI/node_modules" ]] || die "run: cd $UI && npm install"

cd "$UI"
GAIA_ROOT="$ROOT" npm run test:unit:fusion
GAIA_ROOT="$ROOT" npm run build

if [[ "${FUSION_PREFLIGHT_E2E:-0}" == "1" ]]; then
  GAIA_ROOT="$ROOT" npm run test:e2e:fusion
fi

echo ""
echo "CALORIE: fusion UI preflight OK (unit tests + next build)."
echo "Handoff: GAIA_ROOT=$ROOT npm run dev:fusion → http://127.0.0.1:\${FUSION_UI_PORT:-8910}/fusion-s4"
echo "Optional soak rows: npm run fusion:evidence:aux (after Metal data in long_run_signals.jsonl)"
echo "Optional E2E in this script: FUSION_PREFLIGHT_E2E=1 $ROOT/scripts/preflight_fusion_ui_live.sh"
echo "Slow Metal API test: FUSION_MATRIX_E2E=1 GAIA_ROOT=$ROOT npm run test:e2e:fusion"
echo "Production: set FUSION_CHALLENGE_LEDGER_SECRET for POST /api/fusion/challenge-ledger"
