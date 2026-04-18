#!/usr/bin/env bash
# GaiaFTCL — Fusion operator surface verification (scripts + TypeScript unit tests + optional Playwright).
# Receipt: exit 0 only if all enabled checks pass. Treat output as audit trail.
#
#   bash scripts/verify_fusion_operator_surface.sh
#
# Env:
#   FUSION_OPERATOR_PLAYWRIGHT=1  — also run Playwright fusion pack (starts dev server; slower).
#   FUSION_OPERATOR_SKIP_NPM=1    — skip npm test:unit:fusion (e.g. no node_modules).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export GAIA_ROOT="$ROOT"
FAIL=0

note_ok() { echo "OK   $*"; }
note_fail() { echo "FAIL $*" >&2; FAIL=1; }
note_skip() { echo "SKIP $*"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " GaiaFTCL Fusion operator surface verify — GAIA_ROOT=$ROOT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for s in \
  fusion_surface.sh \
  fusion_stack_supervise.sh \
  fusion_stack_launch.sh \
  fusion_cell_long_run_runner.sh \
  fusion_cell_long_run_stop.sh \
  fusion_turbo_ide.sh; do
  if bash -n "$ROOT/scripts/$s"; then
    note_ok "bash -n scripts/$s"
  else
    note_fail "bash -n scripts/$s"
  fi
done

shopt -s nullglob
for f in "$ROOT/scripts/"*overnight*; do
  note_fail "forbidden overnight-named script still present: $f"
done
shopt -u nullglob

if bash "$ROOT/scripts/test_fusion_cli.sh"; then
  note_ok "test_fusion_cli.sh"
else
  note_fail "test_fusion_cli.sh"
fi

if command -v jq >/dev/null 2>&1; then
  if jq -e '.long_run.mode and .long_run.max_batches' "$ROOT/deploy/fusion_cell/config.example.json" >/dev/null 2>&1; then
    note_ok "deploy/fusion_cell/config.example.json long_run block"
  else
    note_fail "deploy/fusion_cell/config.example.json missing long_run.mode / long_run.max_batches"
  fi
else
  note_skip "jq not in PATH — long_run JSON check"
fi

if [[ -f "$ROOT/evidence/fusion_control/overnight_signals.jsonl" ]]; then
  echo "WARN evidence/fusion_control/overnight_signals.jsonl exists — stale writer or un-migrated data; run long-run once or remove after backup" >&2
fi

UI_DIR="$ROOT/services/gaiaos_ui_web"
if [[ "${FUSION_OPERATOR_SKIP_NPM:-0}" == "1" ]]; then
  note_skip "npm tests (FUSION_OPERATOR_SKIP_NPM=1)"
elif [[ -d "$UI_DIR/node_modules" ]]; then
  if (cd "$UI_DIR" && GAIA_ROOT="$ROOT" npm run test:unit:fusion --silent); then
    note_ok "npm run test:unit:fusion"
  else
    note_fail "npm run test:unit:fusion"
  fi
else
  note_skip "npm run test:unit:fusion (no services/gaiaos_ui_web/node_modules)"
fi

if [[ "${FUSION_OPERATOR_PLAYWRIGHT:-0}" == "1" ]]; then
  if [[ -d "$UI_DIR/node_modules" ]]; then
    if (cd "$UI_DIR" && GAIA_ROOT="$ROOT" npm run test:e2e:fusion --silent); then
      note_ok "npm run test:e2e:fusion"
    else
      note_fail "npm run test:e2e:fusion"
    fi
  else
    note_fail "FUSION_OPERATOR_PLAYWRIGHT=1 but node_modules missing"
  fi
else
  note_skip "Playwright fusion (set FUSION_OPERATOR_PLAYWRIGHT=1)"
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " CALORIE: fusion operator surface checks passed"
  exit 0
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " REFUSED: one or more fusion operator surface checks failed" >&2
exit 1
