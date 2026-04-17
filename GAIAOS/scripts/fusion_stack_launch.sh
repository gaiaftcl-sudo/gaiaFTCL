#!/usr/bin/env bash
# Fusion stack entrypoint.
#
# Default: foreground supervisor (stack + S⁴ UI) — does not exit until stop UI, Ctrl+C, SIGTERM, or Next.js dies.
#   bash scripts/fusion_stack_launch.sh [local|calibration|sidecar|ui]
#   npm run fusion:stack -- calibration
#
# Legacy detached mode (background Next + long-run loop, then exit — not recommended):
#   FUSION_STACK_DETACHED=1 bash scripts/fusion_stack_launch.sh
#
# Env: FUSION_UI_PORT FUSION_STACK_PROFILE SKIP_LONG_RUN_START FUSION_OPEN_TURBO_TERMINAL
#      FUSION_STACK_SKIP_REGRESSION FUSION_STACK_IGNORE_SIGHUP FUSION_STACK_REUSE_UI
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${FUSION_STACK_DETACHED:-0}" == "1" ]]; then
  echo "⚠️  FUSION_STACK_DETACHED=1 — legacy mode (nohup UI, script exits). Prefer foreground supervisor."
  UI_PORT="${FUSION_UI_PORT:-8910}"
  export GAIA_ROOT="$ROOT"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " GaiaFTCL — fusion stack launch (DETACHED)"
  echo " GAIA_ROOT=$ROOT"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bash "$ROOT/scripts/test_fusion_mesh_mooring_stack.sh" || {
    echo "⚠️  regression had failures — continuing launch"
  }
  mkdir -p "$ROOT/evidence/fusion_control"
  SKIP_LR="${SKIP_LONG_RUN_START:-0}"
  if [[ "$SKIP_LR" != "1" ]]; then
    PID_FILE="$ROOT/evidence/fusion_control/fusion_cell_long_run.pid"
    if [[ -f "$PID_FILE" ]]; then
      pid="$(tr -d ' \n' <"$PID_FILE" || true)"
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "▶ Long-run cell loop already running pid=$pid"
      else
        echo "▶ Starting long-run cell loop…"
        nohup env \
          FUSION_LONG_RUN_MODE="${FUSION_LONG_RUN_MODE:-nonstop}" \
          FUSION_LONG_RUN_MAX_ITERATIONS="${FUSION_LONG_RUN_MAX_ITERATIONS:-0}" \
          bash "$ROOT/scripts/fusion_cell_long_run_runner.sh" >>"$ROOT/evidence/fusion_control/fusion_cell_long_run.console.log" 2>&1 &
        echo $! >"$PID_FILE"
        echo "   pid=$(cat "$PID_FILE")"
      fi
    else
      echo "▶ Starting long-run cell loop…"
      nohup env \
        FUSION_LONG_RUN_MODE="${FUSION_LONG_RUN_MODE:-nonstop}" \
        FUSION_LONG_RUN_MAX_ITERATIONS="${FUSION_LONG_RUN_MAX_ITERATIONS:-0}" \
        bash "$ROOT/scripts/fusion_cell_long_run_runner.sh" >>"$ROOT/evidence/fusion_control/fusion_cell_long_run.console.log" 2>&1 &
      echo $! >"$PID_FILE"
      echo "   pid=$(cat "$PID_FILE")"
    fi
  fi
  UI_DIR="$ROOT/services/gaiaos_ui_web"
  cd "$UI_DIR"
  if [[ ! -d node_modules ]]; then
    echo "▶ npm install (first run)…"
    npm install
  fi
  if lsof -i ":$UI_PORT" -sTCP:LISTEN -Pn >/dev/null 2>&1; then
    echo "▶ Port $UI_PORT already listening — reusing"
  else
    export GAIA_ROOT="$ROOT"
    nohup npm run dev -- -p "$UI_PORT" >"$ROOT/evidence/fusion_control/fusion_s4_ui_dev.log" 2>&1 &
    echo $! >"$ROOT/evidence/fusion_control/fusion_s4_ui_dev.pid"
    sleep 5
  fi
  URL="http://127.0.0.1:${UI_PORT}/fusion-s4"
  open "$URL" 2>/dev/null || true
  echo " CALORIE (detached): $URL"
  exit 0
fi

exec bash "$ROOT/scripts/fusion_stack_supervise.sh" "$@"
