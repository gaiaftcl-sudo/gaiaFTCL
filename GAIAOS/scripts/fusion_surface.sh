#!/usr/bin/env bash
# Single CLI surface for Fusion on Mac: moor (stack + UI), long-run loop, stop.
#
#   bash scripts/fusion_surface.sh help
#   bash scripts/fusion_surface.sh moor [--profile local|sidecar|ui] [--nonstop|--iterations N] [--skip-long-run] [--skip-regression]
#   bash scripts/fusion_surface.sh stack [local|sidecar|ui]
#   bash scripts/fusion_surface.sh long-run start [--nonstop|--iterations N]
#   bash scripts/fusion_surface.sh long-run stop
#
# --nonstop (default) — long-run child runs until LONG_RUN_STOP / SIGTERM.
# --iterations N — long-run child exits after N batch iterations (see deploy/fusion_cell/config.json long_run).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
cd "$ROOT"

usage() {
  echo "GaiaFTCL fusion surface (GAIA_ROOT=$GAIA_ROOT)"
  echo "  moor [--profile local|sidecar|ui] [--nonstop|--iterations N] [--skip-long-run] [--skip-regression]"
  echo "  stack [local|sidecar|ui]"
  echo "  long-run start [--nonstop|--iterations N]   |   long-run stop"
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  help|-h|--help)
    usage
    ;;
  moor)
    if [[ "${FUSION_SKIP_MOOR_PREFLIGHT:-0}" != "1" ]]; then
      bash "$ROOT/scripts/fusion_moor_preflight.sh" || exit $?
    fi
    PROFILE="local"
    SKIP_LR="0"
    SKIP_REG="0"
    export FUSION_LONG_RUN_MODE="${FUSION_LONG_RUN_MODE:-nonstop}"
    export FUSION_LONG_RUN_MAX_ITERATIONS="${FUSION_LONG_RUN_MAX_ITERATIONS:-0}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --profile)
          PROFILE="${2:?}"
          shift 2
          ;;
        --skip-long-run) SKIP_LR="1"; shift ;;
        --skip-regression) SKIP_REG="1"; shift ;;
        --nonstop)
          export FUSION_LONG_RUN_MODE="nonstop"
          export FUSION_LONG_RUN_MAX_ITERATIONS="0"
          shift
          ;;
        --iterations)
          export FUSION_LONG_RUN_MODE="iterations"
          export FUSION_LONG_RUN_MAX_ITERATIONS="${2:?}"
          shift 2
          ;;
        *)
          echo "REFUSED: unknown moor flag '$1'"
          exit 1
          ;;
      esac
    done
    [[ "$SKIP_REG" == "1" ]] && export FUSION_STACK_SKIP_REGRESSION=1
    [[ "$SKIP_LR" == "1" ]] && export SKIP_LONG_RUN_START=1
    exec bash "$ROOT/scripts/fusion_stack_supervise.sh" "$PROFILE"
    ;;
  stack)
    PROFILE="${1:-local}"
    exec bash "$ROOT/scripts/fusion_stack_supervise.sh" "$PROFILE"
    ;;
  long-run)
    sub="${1:-}"
    shift || true
    case "$sub" in
      start)
        export FUSION_LONG_RUN_MODE="${FUSION_LONG_RUN_MODE:-nonstop}"
        export FUSION_LONG_RUN_MAX_ITERATIONS="${FUSION_LONG_RUN_MAX_ITERATIONS:-0}"
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --nonstop)
              export FUSION_LONG_RUN_MODE="nonstop"
              export FUSION_LONG_RUN_MAX_ITERATIONS="0"
              shift
              ;;
            --iterations)
              export FUSION_LONG_RUN_MODE="iterations"
              export FUSION_LONG_RUN_MAX_ITERATIONS="${2:?}"
              shift 2
              ;;
            *)
              echo "REFUSED: unknown flag '$1'"
              exit 1
              ;;
          esac
        done
        exec bash "$ROOT/scripts/fusion_cell_long_run_runner.sh"
        ;;
      stop)
        exec bash "$ROOT/scripts/fusion_cell_long_run_stop.sh"
        ;;
      *)
        echo "REFUSED: fusion_surface.sh long-run start|stop"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "REFUSED: unknown command '$cmd'"
    usage
    exit 1
    ;;
esac
