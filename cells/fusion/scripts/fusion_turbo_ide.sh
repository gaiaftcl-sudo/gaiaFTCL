#!/usr/bin/env bash
# GaiaFTCL — Borland-style Turbo IDE for long-run fusion cell + optional DMG build + mesh bridge probes.
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "$0")" && pwd)/lib/turbo_paths.sh"
GAIA_ROOT="$(turbo_resolve_gaia_root "$0")"
cd "$GAIA_ROOT"

# shellcheck source=/dev/null
source "$GAIA_ROOT/scripts/lib/turbo_frames.sh"
# shellcheck source=/dev/null
source "$GAIA_ROOT/scripts/lib/turbo_keys.sh"
if [[ -f "$GAIA_ROOT/scripts/lib/fusion_mooring.sh" ]]; then
  # shellcheck source=/dev/null
  source "$GAIA_ROOT/scripts/lib/fusion_mooring.sh"
fi

turbo_init_colors

EVID="${FUSION_TURBO_EVID:-$GAIA_ROOT/evidence/fusion_control}"
mkdir -p "$EVID"
PID_FILE="$EVID/fusion_cell_long_run.pid"
DMG_PID_FILE="$EVID/dmg_build.pid"
STOP_REL="${FUSION_LONG_RUN_STOPFILE:-evidence/fusion_control/LONG_RUN_STOP}"
[[ "$STOP_REL" = /* ]] && STOP_FILE="$STOP_REL" || STOP_FILE="$GAIA_ROOT/$STOP_REL"
JSONL_REL="${FUSION_LONG_RUN_JSONL:-evidence/fusion_control/long_run_signals.jsonl}"
[[ "$JSONL_REL" = /* ]] && JSONL="$JSONL_REL" || JSONL="$GAIA_ROOT/$JSONL_REL"
PROJ="${FUSION_PROJECTION_JSON:-$GAIA_ROOT/deploy/fusion_mesh/fusion_projection.json}"
DMG_LOG="$EVID/dmg_build.log"
LONG_RUN_LOG="$EVID/fusion_cell_long_run.console.log"
PERIODIC_PID_FILE="$EVID/turbo_periodic.pid"

trap 'stty sane 2>/dev/null || true' EXIT

bridge_path() {
  local name="$1"
  if [[ -x "$GAIA_ROOT/bin/$name" ]]; then
    printf '%s\n' "$GAIA_ROOT/bin/$name"
  elif [[ -x "$GAIA_ROOT/deploy/mac_cell_mount/bin/$name" ]]; then
    printf '%s\n' "$GAIA_ROOT/deploy/mac_cell_mount/bin/$name"
  else
    printf '%s\n' ""
  fi
}

mooring_heartbeat_bin() {
  bridge_path "fusion_mesh_mooring_heartbeat.sh"
}

long_run_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local p
  p="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null
}

dmg_build_running() {
  [[ -f "$DMG_PID_FILE" ]] || return 1
  local p
  p="$(cat "$DMG_PID_FILE" 2>/dev/null || true)"
  [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null
}

gaia_dmg_ready() {
  [[ -f "$GAIA_ROOT/scripts/build_gaiaftcl_facade_dmg.sh" ]] && [[ -d "$GAIA_ROOT/services/gaiaftcl_sovereign_facade" ]]
}

draw_refused_panel() {
  local msg="$1"
  turbo_top
  turbo_row "  ${RD}${B}REFUSED${RST} — $msg"
  turbo_mid
  turbo_row "  Set ${BR}GAIA_ROOT${RST} to a full GaiaFTCL checkout if paths are wrong."
  turbo_row "  Projection: ${PROJ}"
  turbo_bot
}

draw_bridge_panel() {
  local title="$1"
  local exe="$2"
  local out
  out="$(mktemp)"
  set +e
  FUSION_PROJECTION_JSON="$PROJ" "$exe" >"$out" 2>&1
  local rc=$?
  set -e
  turbo_top
  turbo_row "  ${B}$title${RST}  exit=$rc"
  turbo_mid
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    turbo_row "  ${line:0:62}"
  done < <(head -n 18 "$out")
  turbo_bot
  rm -f "$out"
  printf '\n'
  read -rsp $'Press Enter…' -n 1 _ || true
  printf '\n'
}

signals_jsonl_for_tail() {
  printf '%s\n' "$JSONL"
}

draw_tail_panel() {
  turbo_top
  turbo_row "  ${B}signals JSONL${RST} (last line)"
  turbo_mid
  local sj
  sj="$(signals_jsonl_for_tail)"
  if [[ ! -f "$sj" ]]; then
    turbo_row "  (file missing — start long-run loop first)"
  else
    local last
    last="$(tail -n 1 "$sj" 2>/dev/null || true)"
    if [[ -z "$last" ]]; then
      turbo_row "  (empty)"
    elif command -v jq >/dev/null 2>&1 && echo "$last" | jq -e . >/dev/null 2>&1; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        turbo_row "  ${line:0:62}"
      done < <(echo "$last" | jq -C . 2>/dev/null | head -n 14 || echo "$last" | head -c 200)
    else
      turbo_row "  ${last:0:62}"
    fi
  fi
  turbo_bot
}

draw_main() {
  turbo_clear
  turbo_title_bar " GAIAFTCL FUSION TURBO IDE "
  turbo_top
  turbo_row "  ${B}GAIA_ROOT${RST}  ${GAIA_ROOT:0:46}"
  turbo_mid
  turbo_row_val "Projection (S4) " "$PROJ"
  if [[ -f "$PROJ" ]]; then
    turbo_row_val "plant / DIF     " "$(jq -r '[.plant_flavor,.dif_profile] | @tsv' "$PROJ" 2>/dev/null || echo "?")"
  else
    turbo_row "  ${RD}fusion_projection.json missing${RST}"
  fi
  if declare -F fusion_mooring_mesh_fresh >/dev/null 2>&1; then
    local mf pe
    mf="STALE"
    fusion_mooring_mesh_fresh && mf="FRESH"
    pe="no"
    fusion_payment_eligible && pe="YES"
    turbo_row_val "Mesh mooring     " "$mf (≤${FUSION_MESH_HEARTBEAT_MAX_SEC:-86400}s)"
    turbo_row_val "Payment eligible " "$pe (live HW+id+mount+mesh)"
  fi
  turbo_mid
  if long_run_running; then
    turbo_row_val "Long-run cell   " "${GR}RUNNING pid=$(cat "$PID_FILE")${RST}"
  else
    turbo_row_val "Long-run cell   " "stopped"
  fi
  if dmg_build_running; then
    turbo_row_val "DMG build       " "${GR}RUNNING pid=$(cat "$DMG_PID_FILE")${RST}"
  else
    turbo_row_val "DMG build       " "idle"
  fi
  turbo_row_val "JSONL           " "$JSONL"
  turbo_row_val "DMG log         " "$DMG_LOG"
  turbo_mid
  turbo_row "  ${B}F1${RST} Help  ${B}F2${RST} DMG(bg) ${B}F3${RST} long-run ${B}F4${RST} stop  ${B}F5${RST} tail"
  turbo_row "  ${B}F6${RST} TORAX ${B}F7${RST} MARTe2 ${B}F8${RST} matrix ${B}F9${RST} demo ${B}F10${RST}/0 quit ${B}h${RST} mesh ping"
  turbo_row "  Digits ${B}1-9${RST} = F1-F9, ${B}0${RST} = quit  ${B}q${RST} quit"
  turbo_bot
  if ! gaia_dmg_ready; then
    turbo_top
    turbo_row "  ${BR}DMG build from this tree: REFUSED (missing Swift facade or script).${RST}"
    turbo_row "  Long-run loop / bridges still work if binaries + config exist."
    turbo_bot
  fi
}

action_help() {
  turbo_clear
  turbo_title_bar " FUSION TURBO IDE — HELP "
  turbo_top
  turbo_row "  Stop long-run: F4 or  touch $STOP_FILE"
  turbo_row "  Bridge config:  deploy/fusion_mesh/fusion_projection.json"
  turbo_row "  Env overrides:  FUSION_PROJECTION_JSON  GAIA_ROOT"
  turbo_row "  Runtime env:     ~/.gaiaftcl/fusion_runtime.env (optional)"
  turbo_row "  Periodic panel:  FUSION_TURBO_PERIODIC_PANEL_SEC (e.g. 3600)"
  turbo_mid
  turbo_row "  Mooring: deploy/fusion_mesh/FUSION_PLANT_MOORING_AND_MESH_PAYMENT.md"
  turbo_row "  NATS ping: bin/fusion_mesh_mooring_heartbeat.sh (nats CLI + NATS_URL)"
  turbo_row "  Strict gate: FUSION_MESH_MOORING_REQUIRED=1 long-run skips batch if mesh stale"
  turbo_bot
  read -rsp $'Press Enter…' -n 1 _ || true
}

action_mooring_heartbeat() {
  local hb
  hb="$(mooring_heartbeat_bin)"
  if [[ -z "$hb" ]]; then
    draw_refused_panel "fusion_mesh_mooring_heartbeat.sh not in bin/ or deploy/mac_cell_mount/bin/"
    read -rsp $'Press Enter…' -n 1 _ || true
    return
  fi
  draw_bridge_panel "fusion_mesh_mooring_heartbeat" "$hb"
}

action_dmg_bg() {
  if ! gaia_dmg_ready; then
    draw_refused_panel "full DMG build needs checkout + services/gaiaftcl_sovereign_facade"
    read -rsp $'Press Enter…' -n 1 _ || true
    return
  fi
  if dmg_build_running; then
    return
  fi
  mkdir -p "$(dirname "$DMG_LOG")"
  nohup bash "$GAIA_ROOT/scripts/build_gaiaftcl_facade_dmg.sh" >>"$DMG_LOG" 2>&1 &
  echo $! >"$DMG_PID_FILE"
}

action_long_run_start() {
  if long_run_running; then
    return
  fi
  mkdir -p "$(dirname "$JSONL")" "$(dirname "$LONG_RUN_LOG")"
  export FUSION_PROJECTION_JSON="$PROJ"
  nohup env \
    FUSION_LONG_RUN_MODE="${FUSION_LONG_RUN_MODE:-nonstop}" \
    FUSION_LONG_RUN_MAX_ITERATIONS="${FUSION_LONG_RUN_MAX_ITERATIONS:-0}" \
    bash "$GAIA_ROOT/scripts/fusion_cell_long_run_runner.sh" >>"$LONG_RUN_LOG" 2>&1 &
  echo $! >"$PID_FILE"
}

action_long_run_stop() {
  mkdir -p "$(dirname "$STOP_FILE")"
  touch "$STOP_FILE"
  if [[ -f "$PID_FILE" ]]; then
    local p
    p="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
  fi
}

action_demo() {
  action_long_run_start
  {
    echo "[fusion_turbo_ide] demo: long-run start requested; stop with F4 or touch STOP file"
    echo "[fusion_turbo_ide] JSONL=$JSONL"
  } >>"$LONG_RUN_LOG"
  if [[ -n "${FUSION_TURBO_PERIODIC_PANEL_SEC:-}" ]]; then
    if [[ -f "$PERIODIC_PID_FILE" ]]; then
      local op
      op="$(cat "$PERIODIC_PID_FILE" 2>/dev/null || true)"
      [[ -n "$op" ]] && kill "$op" 2>/dev/null || true
    fi
    (
      while true; do
        sleep "${FUSION_TURBO_PERIODIC_PANEL_SEC}"
        bash "$GAIA_ROOT/scripts/best_control_test_ever.sh" >>"$EVID/turbo_periodic.log" 2>&1 || true
      done
    ) &
    echo $! >"$PERIODIC_PID_FILE"
  fi
}

action_control_matrix() {
  stty sane 2>/dev/null || true
  bash "$GAIA_ROOT/scripts/best_control_test_ever.sh" || true
  read -rsp $'Press Enter…' -n 1 _ || true
}

main_loop() {
  while true; do
    draw_main
    printf '%s' "${CY}${B}>${RST} "
    key="$(turbo_read_key)"
    printf '\n'
    case "$key" in
      f1|'1') action_help ;;
      f2|'2') action_dmg_bg ;;
      f3|'3') action_long_run_start ;;
      f4|'4') action_long_run_stop ;;
      f5|'5')
        draw_tail_panel
        read -rsp $'Press Enter…' -n 1 _ || true
        ;;
      f6|'6')
        bt="$(bridge_path mcp_bridge_torax)"
        if [[ -z "$bt" ]]; then
          draw_refused_panel "mcp_bridge_torax not found under bin/ or deploy/mac_cell_mount/bin/"
          read -rsp $'Press Enter…' -n 1 _ || true
        else
          draw_bridge_panel "mcp_bridge_torax" "$bt"
        fi
        ;;
      f7|'7')
        bm="$(bridge_path mcp_bridge_marte2)"
        if [[ -z "$bm" ]]; then
          draw_refused_panel "mcp_bridge_marte2 not found under bin/ or deploy/mac_cell_mount/bin/"
          read -rsp $'Press Enter…' -n 1 _ || true
        else
          draw_bridge_panel "mcp_bridge_marte2" "$bm"
        fi
        ;;
      f8|'8') action_control_matrix ;;
      f9|'9') action_demo ;;
      f10|'0'|q|Q) break ;;
      h|H) action_mooring_heartbeat ;;
      *) ;;
    esac
  done
}

main_loop
