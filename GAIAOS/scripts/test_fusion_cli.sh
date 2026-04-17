#!/usr/bin/env bash
# GaiaFTCL — Fusion CLI contract tests (no supervisor, no long-run start).
# Receipt: exit 0 iff all checks pass.
#
#   bash scripts/test_fusion_cli.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
FS="$ROOT/scripts/fusion_surface.sh"
FAIL=0

ok() { echo "OK   $*"; }
bad() { echo "FAIL $*" >&2; FAIL=1; }

if bash "$FS" help >/dev/null 2>&1; then
  ok "fusion_surface.sh help (exit 0)"
else
  bad "fusion_surface.sh help (exit 0)"
fi

# Avoid SIGPIPE under pipefail when grep -q closes the pipe early.
HELP_OUT="$(bash "$FS" help 2>/dev/null || true)"
if grep -q moor <<<"$HELP_OUT"; then
  ok "fusion_surface.sh help mentions moor"
else
  bad "fusion_surface.sh help mentions moor"
fi

if bash "$FS" long-run stop >/dev/null 2>&1; then
  ok "fusion_surface.sh long-run stop (touches LONG_RUN_STOP)"
else
  bad "fusion_surface.sh long-run stop"
fi

if bash "$FS" not-a-real-command >/dev/null 2>&1; then
  bad "unknown command should exit non-zero"
else
  ok "unknown command exits non-zero"
fi

if bash "$FS" long-run >/dev/null 2>&1; then
  bad "long-run without start|stop should exit non-zero"
else
  ok "long-run without subcommand exits non-zero"
fi

# Missing value after --iterations must abort before exec (bash :? on $2).
if bash "$FS" long-run start --iterations >/dev/null 2>&1; then
  bad "long-run start --iterations (missing N) should exit non-zero"
else
  ok "long-run start --iterations requires a value"
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "CALORIE: fusion CLI contract tests passed"
  exit 0
fi
echo "REFUSED: fusion CLI contract tests failed" >&2
exit 1
