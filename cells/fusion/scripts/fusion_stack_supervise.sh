#!/usr/bin/env bash
# Foreground supervisor: start selected stack + Next S4 UI; exit only on child failure,
# SIGINT/SIGTERM (human terminal stop), or UI/file stop request.
#
# Usage:
#   bash scripts/fusion_stack_supervise.sh [profile]
# Profiles:
#   local        — mooring regression (optional), long-run cell loop (optional), Next UI (default)
#   calibration  — rebuild default.metallib (macOS), ghost-primed long-run receipts, then same as local
#   sidecar      — docker-compose.fusion-sidecar.yml up -d, then same as local
#   ui           — Next UI only
#
# Env:
#   GAIA_ROOT, FUSION_UI_PORT (default 8910)
#   SKIP_LONG_RUN_START=1, FUSION_STACK_SKIP_REGRESSION=1
#   FUSION_STACK_IGNORE_SIGHUP=1 — ignore hangup (terminal close) on supervisor only
#   FUSION_STACK_REUSE_UI=1 — if UI port already listening, do not spawn a second Next
#   FUSION_STACK_DETACHED=0 — (via fusion_stack_launch legacy path only)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export GAIA_ROOT="$ROOT"

PROFILE_RAW="${1:-${FUSION_STACK_PROFILE:-local}}"
PROFILE="$(printf '%s' "$PROFILE_RAW" | tr '[:upper:]' '[:lower:]')"
if [[ "$PROFILE" == "calibration" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "▶ calibration: scripts/build_metal_lib.sh"
    bash "$ROOT/scripts/build_metal_lib.sh"
  else
    echo "▶ calibration: skip metallib (host is not Darwin)"
  fi
  export FUSION_LONG_RUN_GHOST_PRIME=1
  PROFILE=local
fi
UI_PORT="${FUSION_UI_PORT:-8910}"
EVID="$ROOT/evidence/fusion_control"
mkdir -p "$EVID"
STOP_FILE="$EVID/FUSION_STACK_STOP_REQUESTED"
UI_LOG="$EVID/fusion_s4_ui_dev.log"
UI_PID_FILE="$EVID/fusion_s4_ui_supervise.pid"
LONG_RUN_PID_FILE="$EVID/fusion_cell_long_run.pid"

next_pid=""
docker_started=0

rm -f "$STOP_FILE"

if [[ "${FUSION_STACK_IGNORE_SIGHUP:-0}" == "1" ]]; then
  trap '' HUP
fi

shutdown_children() {
  local op
  if [[ -n "${next_pid}" ]] && kill -0 "$next_pid" 2>/dev/null; then
    echo "[supervisor] stopping Next.js pid=$next_pid"
    kill -TERM "$next_pid" 2>/dev/null || true
    wait "$next_pid" 2>/dev/null || true
  fi
  if [[ -f "$LONG_RUN_PID_FILE" ]]; then
    op="$(tr -d ' \n' <"$LONG_RUN_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$op" ]] && kill -0 "$op" 2>/dev/null; then
      echo "[supervisor] stopping long-run cell loop pid=$op"
      kill -TERM "$op" 2>/dev/null || true
    fi
  fi
}

docker_down() {
  if [[ "$docker_started" -eq 1 ]]; then
    echo "[supervisor] docker compose down (fusion-sidecar)"
    docker compose -f "$ROOT/docker-compose.fusion-sidecar.yml" down >/dev/null 2>&1 || true
    docker_started=0
  fi
}

trap 'echo "[supervisor] SIGINT — shutdown"; shutdown_children; docker_down; rm -f "$UI_PID_FILE"; exit 130' INT
trap 'echo "[supervisor] SIGTERM — shutdown"; shutdown_children; docker_down; rm -f "$UI_PID_FILE"; exit 143' TERM
trap 'stty sane 2>/dev/null || true' EXIT

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " GaiaFTCL — fusion stack supervisor (foreground)"
echo " GAIA_ROOT=$ROOT"
echo " profile=$PROFILE  UI_PORT=$UI_PORT"
echo " Stop: UI button → POST /api/fusion/stack-stop | or: touch $STOP_FILE"
echo "       Terminal: Ctrl+C or SIGTERM"
echo " This process does not exit when regression warns — only on UI/child failure/stop."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$PROFILE" == "sidecar" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "REFUSED: profile=sidecar requires docker in PATH"
    exit 1
  fi
  echo "▶ docker compose up -d (fusion-sidecar)"
  docker compose -f "$ROOT/docker-compose.fusion-sidecar.yml" up -d --build
  docker_started=1
  sleep 3
elif [[ "$PROFILE" == "local" || "$PROFILE" == "ui" ]]; then
  :
else
  echo "REFUSED: unknown profile '$PROFILE' (use local | calibration | sidecar | ui)"
  exit 1
fi

if [[ "${FUSION_STACK_SKIP_REGRESSION:-0}" != "1" ]]; then
  echo "▶ Regression: test_fusion_mesh_mooring_stack.sh"
  bash "$ROOT/scripts/test_fusion_mesh_mooring_stack.sh" || {
    echo "⚠️  regression reported failures — supervisor continues (stack stays up)"
  }
else
  echo "▶ FUSION_STACK_SKIP_REGRESSION=1 — skip regression"
fi

SKIP_LR="${SKIP_LONG_RUN_START:-0}"
if [[ "$PROFILE" != "ui" ]] && [[ "$SKIP_LR" != "1" ]]; then
  if [[ -f "$LONG_RUN_PID_FILE" ]]; then
    pid="$(tr -d ' \n' <"$LONG_RUN_PID_FILE" || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "▶ Long-run cell loop already running pid=$pid"
    else
      echo "▶ Starting long-run cell loop…"
      nohup env \
        FUSION_LONG_RUN_MODE="${FUSION_LONG_RUN_MODE:-nonstop}" \
        FUSION_LONG_RUN_MAX_ITERATIONS="${FUSION_LONG_RUN_MAX_ITERATIONS:-0}" \
        bash "$ROOT/scripts/fusion_cell_long_run_runner.sh" >>"$EVID/fusion_cell_long_run.console.log" 2>&1 &
      echo $! >"$LONG_RUN_PID_FILE"
      echo "   pid=$(cat "$LONG_RUN_PID_FILE")"
    fi
  else
    echo "▶ Starting long-run cell loop…"
    nohup env \
      FUSION_LONG_RUN_MODE="${FUSION_LONG_RUN_MODE:-nonstop}" \
      FUSION_LONG_RUN_MAX_ITERATIONS="${FUSION_LONG_RUN_MAX_ITERATIONS:-0}" \
      bash "$ROOT/scripts/fusion_cell_long_run_runner.sh" >>"$EVID/fusion_cell_long_run.console.log" 2>&1 &
    echo $! >"$LONG_RUN_PID_FILE"
    echo "   pid=$(cat "$LONG_RUN_PID_FILE")"
  fi
else
  echo "▶ Long-run cell loop not started (profile=ui or SKIP_LONG_RUN_START=1)"
fi

UI_DIR="$ROOT/services/gaiaos_ui_web"
if [[ ! -d "$UI_DIR" ]]; then
  echo "REFUSED: missing $UI_DIR"
  docker_down
  exit 1
fi

if lsof -i ":$UI_PORT" -sTCP:LISTEN -Pn >/dev/null 2>&1; then
  if [[ "${FUSION_STACK_REUSE_UI:-0}" == "1" ]]; then
    echo "▶ Port $UI_PORT already listening — FUSION_STACK_REUSE_UI=1, not starting a second Next.js"
    next_pid=""
  else
    echo "REFUSED: port $UI_PORT already in use. Set FUSION_STACK_REUSE_UI=1 to attach supervisor without spawning Next, or free the port."
    docker_down
    exit 1
  fi
else
  cd "$UI_DIR"
  if [[ ! -d node_modules ]]; then
    echo "▶ npm install (first run)…"
    npm install
  fi
  export GAIA_ROOT="$ROOT"
  echo "▶ Starting Next.js S4 UI on :$UI_PORT (foreground child; logs also $UI_LOG)"
  : >"$UI_LOG"
  npm run dev -- -p "$UI_PORT" >>"$UI_LOG" 2>&1 &
  next_pid=$!
  echo "$next_pid" >"$UI_PID_FILE"
  echo "   next_pid=$next_pid"
  cd "$ROOT"
  sleep 4
fi

URL="http://127.0.0.1:${UI_PORT}/fusion-s4"
echo "▶ Open $URL (browser)"
if [[ "$(uname -s)" == "Darwin" ]]; then
  open "$URL" || true
else
  echo "   open manually: $URL"
fi

if [[ "$(uname -s)" == "Darwin" ]] && [[ "${FUSION_OPEN_TURBO_TERMINAL:-0}" == "1" ]]; then
  qroot=$(printf %q "$ROOT")
  osascript <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "cd ${qroot} && bash scripts/fusion_turbo_ide.sh"
end tell
APPLESCRIPT
  echo "▶ Opened Terminal.app with fusion_turbo_ide.sh"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " RUNNING — supervisor blocked until stop or Next.js exit"
echo " UI: $URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while true; do
  if [[ -f "$STOP_FILE" ]]; then
    echo "[supervisor] stop file present — shutting down"
    rm -f "$STOP_FILE"
    shutdown_children
    docker_down
    rm -f "$UI_PID_FILE"
    exit 0
  fi
  if [[ -n "${next_pid}" ]]; then
    if ! kill -0 "$next_pid" 2>/dev/null; then
      rc=0
      wait "$next_pid" || rc=$?
      echo "[supervisor] Next.js exited (code=$rc) — shutting down stack"
      shutdown_children
      docker_down
      rm -f "$UI_PID_FILE"
      exit "$rc"
    fi
  fi
  sleep 2
done
