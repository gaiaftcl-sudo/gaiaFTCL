#!/usr/bin/env bash
# Start / stop / status for M8 benchmark feeder processes (PID files under evidence/fusion_control/).
# Used by FusionMacCLI: --cli feeder <start|stop|status> [nstxu|pcssp|all]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EV="$ROOT/evidence/fusion_control"
mkdir -p "$EV"

nstxu_pid="$EV/feed_nstxu.pid"
pcssp_pid="$EV/feed_pcssp.pid"

usage() {
  echo "Usage: bash scripts/fusion_feeder_service.sh {start|stop|status} [nstxu|pcssp|all]" >&2
  echo "  nstxu  — loops scripts/feed_nstxu.sh (shadow + optional NATS)" >&2
  echo "  pcssp  — loops scripts/feed_pcssp.sh (NATS required per shot)" >&2
  echo "  all    — start/stop both when configured" >&2
  exit 2
}

running() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local raw
  raw="$(tr -d ' \t\r\n' <"$f" || true)"
  [[ "$raw" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$raw" 2>/dev/null
}

stop_one() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local raw
  raw="$(tr -d ' \t\r\n' <"$f" || true)"
  [[ "$raw" =~ ^[0-9]+$ ]] || { rm -f "$f"; return 0; }
  kill "$raw" 2>/dev/null || true
  sleep 0.2
  kill -0 "$raw" 2>/dev/null && kill -9 "$raw" 2>/dev/null || true
  rm -f "$f"
}

start_nstxu() {
  if running "$nstxu_pid"; then
    echo "REFUSED: feed_nstxu already running (pid $(tr -d ' \t\r\n' <"$nstxu_pid"))"
    return 1
  fi
  rm -f "$nstxu_pid"
  nohup bash "$ROOT/scripts/feed_nstxu.sh" >>"$EV/feed_nstxu.log" 2>&1 &
  echo $! >"$nstxu_pid"
  echo "CALORIE: feed_nstxu started pid=$(tr -d ' \t\r\n' <"$nstxu_pid") log=$EV/feed_nstxu.log"
}

start_pcssp() {
  if running "$pcssp_pid"; then
    echo "REFUSED: feed_pcssp already running (pid $(tr -d ' \t\r\n' <"$pcssp_pid"))"
    return 1
  fi
  rm -f "$pcssp_pid"
  (
    while true; do
      bash "$ROOT/scripts/feed_pcssp.sh" >>"$EV/feed_pcssp.log" 2>&1 || true
      sleep 30
    done
  ) &
  echo $! >"$pcssp_pid"
  echo "CALORIE: feed_pcssp loop started pid=$(tr -d ' \t\r\n' <"$pcssp_pid") log=$EV/feed_pcssp.log"
}

json_status() {
  local n_run p_run n_raw p_raw
  n_run=false
  p_run=false
  running "$nstxu_pid" && n_run=true
  running "$pcssp_pid" && p_run=true
  n_raw=""
  p_raw=""
  [[ -f "$nstxu_pid" ]] && n_raw="$(tr -d ' \t\r\n' <"$nstxu_pid" || true)"
  [[ -f "$pcssp_pid" ]] && p_raw="$(tr -d ' \t\r\n' <"$pcssp_pid" || true)"
  command -v jq >/dev/null 2>&1 || {
    echo "{\"schema\":\"gaiaftcl_fusion_feeder_service_status_v1\",\"feed_nstxu_running\":$n_run,\"feed_pcssp_loop_running\":$p_run}"
    return 0
  }
  jq -n \
    --arg nstxu_pf "$nstxu_pid" \
    --arg pcssp_pf "$pcssp_pid" \
    --arg nstxu_raw "$n_raw" \
    --arg pcssp_raw "$p_raw" \
    --argjson nstxu_run "$n_run" \
    --argjson pcssp_run "$p_run" \
    '{
      schema: "gaiaftcl_fusion_feeder_service_status_v1",
      feed_nstxu: { pid_file: $nstxu_pf, pid: (if $nstxu_raw == "" then null else $nstxu_raw end), running: $nstxu_run },
      feed_pcssp_loop: { pid_file: $pcssp_pf, pid: (if $pcssp_raw == "" then null else $pcssp_raw end), running: $pcssp_run }
    }'
}

cmd="${1:-}"
target="${2:-all}"
[[ -n "$cmd" ]] || usage

case "$cmd" in
  start)
    case "$target" in
      nstxu) start_nstxu ;;
      pcssp) start_pcssp ;;
      all)
        start_nstxu || true
        start_pcssp || true
        ;;
      *) usage ;;
    esac
    ;;
  stop)
    case "$target" in
      nstxu) stop_one "$nstxu_pid" ;;
      pcssp) stop_one "$pcssp_pid" ;;
      all)
        stop_one "$nstxu_pid"
        stop_one "$pcssp_pid"
        ;;
      *) usage ;;
    esac
    echo "CALORIE: feeder stop ($target) issued"
    ;;
  status)
    json_status
    ;;
  *)
    usage
    ;;
esac
