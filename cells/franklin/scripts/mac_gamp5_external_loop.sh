#!/usr/bin/env zsh
# Franklin owner-Mac external-loop GAMP5 orchestrator.
# Runs real clone/update/build/launch/validate stages and emits an append-only run receipt.
set -euo pipefail
emulate -LR zsh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRANKLIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FRANKLIN_DIR/../.." && pwd)"

export GAIAFTCL_REPO_ROOT="${GAIAFTCL_REPO_ROOT:-$REPO_ROOT}"
export GAIAHEALTH_REPO_ROOT="${GAIAHEALTH_REPO_ROOT:-$REPO_ROOT}"

EVD_DIR="$REPO_ROOT/cells/health/evidence/mac_gamp5_external_loop"
mkdir -p "$EVD_DIR"
TS="$(date -u "+%Y-%m-%dT%H%M%SZ")"
RUN_ID="mac_gamp5_external_loop_${TS}"
RUN_DIR="$EVD_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"
PHASES_TSV="$RUN_DIR/phases.tsv"
touch "$PHASES_TSV"

REPO_URL="${MAC_GAMP5_REPO_URL:-https://github.com/gaiaftcl-sudo/gaiaFTCL.git}"
OWNER_CONSENT="${MAC_GAMP5_OWNER_CONSENT:-ask}"
CLONE_DIR="${MAC_GAMP5_CLONE_DIR:-$HOME/.gaiaftcl/external-loop/gaiaFTCL}"
OPEN_APP="${MAC_GAMP5_OPEN_APP:-1}"

append_phase() {
  # phase_name exit_code detail
  printf "%s\t%s\t%s\n" "$1" "$2" "$3" >> "$PHASES_TSV"
}

run_phase() {
  local phase="$1"
  shift
  set +e
  "$@"
  local code=$?
  set -e
  append_phase "$phase" "$code" "$*"
  return "$code"
}

owner_consent_gate() {
  if [[ "$OWNER_CONSENT" == "1" ]]; then
    return 0
  fi
  if [[ "$OWNER_CONSENT" == "0" ]]; then
    echo "REFUSED: OWNER_CONSENT=0"
    return 2
  fi
  echo "Owner consent required for bootstrap + license/agreement flow."
  echo "Type EXACTLY: I_AGREE_GAMP5_EXTERNAL_LOOP"
  local line=""
  IFS= read -r line
  [[ "$line" == "I_AGREE_GAMP5_EXTERNAL_LOOP" ]]
}

clone_or_update() {
  mkdir -p "$(dirname "$CLONE_DIR")"
  if [[ -d "$CLONE_DIR/.git" ]]; then
    git -C "$CLONE_DIR" fetch --all --prune
    git -C "$CLONE_DIR" pull --ff-only
  else
    if command -v gh >/dev/null 2>&1; then
      gh repo clone gaiaftcl-sudo/gaiaFTCL "$CLONE_DIR"
    else
      git clone "$REPO_URL" "$CLONE_DIR"
    fi
  fi
}

build_and_launch_macfranklin() {
  local target_repo="$1"
  local build_script="$target_repo/cells/health/swift/MacFranklin/build_macfranklin_app.sh"
  [[ -f "$build_script" ]] || { echo "missing $build_script" >&2; return 2; }
  zsh "$build_script"
  if [[ "$OPEN_APP" == "1" ]]; then
    open "$target_repo/cells/health/swift/MacFranklin/.build/MacFranklin.app"
  fi
}

wait_for_runtime_state() {
  local target_repo="$1"
  local timeout_s="${MAC_GAMP5_STATE_TIMEOUT_S:-90}"
  local state_dir="$target_repo/cells/health/evidence/macfranklin_state"
  local t=0
  while [[ "$t" -lt "$timeout_s" ]]; do
    if [[ -d "$state_dir" ]] && ls "$state_dir"/state_*.json >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    t=$((t + 2))
  done
  echo "REFUSED: no runtime state snapshot found within ${timeout_s}s at $state_dir" >&2
  return 1
}

run_core_games() {
  local target_repo="$1"
  (cd "$target_repo" && zsh "cells/franklin/tests/test_mac_mesh_cell_narrative_lock.sh") || return 1
  (cd "$target_repo" && zsh "cells/health/scripts/health_cell_gamp5_validate.sh" --skip-cargo-test) || return 1
  (cd "$target_repo" && FRANKLIN_GAMP5_SMOKE=1 /bin/sh "cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh") || return 1
}

run_mcp_observer_games() {
  local target_repo="$1"
  local observer_bin="$target_repo/target/release/mac_gamp5_observer"
  if [[ ! -x "$observer_bin" ]]; then
    (cd "$target_repo" && cargo build -p mac_gamp5_observer --release) || return 2
  fi
  TARGET_REPO="$target_repo" RUN_DIR="$RUN_DIR" "$observer_bin"
}

write_receipt() {
  local final_exit="$1"
  local target_repo="$2"
  local receipt="$RUN_DIR/run_receipt.json"
  local git_short
  git_short="$(git -C "$target_repo" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  local phases_json
  phases_json="$(
    awk -F '\t' '
      BEGIN { print "["; first=1 }
      NF >= 2 {
        name=$1; code=$2; detail=$3
        gsub(/\\/,"\\\\",name); gsub(/"/,"\\\"",name)
        gsub(/\\/,"\\\\",detail); gsub(/"/,"\\\"",detail)
        if (!first) printf(",\n")
        printf("  {\"name\":\"%s\",\"exit\":%d,\"detail\":\"%s\"}", name, code+0, detail)
        first=0
      }
      END { print "\n]" }
    ' "$PHASES_TSV"
  )"
  {
    printf '{\n'
    printf '  "schema": "mac_gamp5_external_loop_receipt_v1",\n'
    printf '  "run_id": "%s",\n' "$RUN_ID"
    printf '  "ts_utc": "%s",\n' "$TS"
    printf '  "repo_root": "%s",\n' "$target_repo"
    printf '  "git_short_sha": "%s",\n' "$git_short"
    printf '  "owner_monitored_local_mac": true,\n'
    printf '  "stages": %s,\n' "$phases_json"
    printf '  "final_exit": %d\n' "$final_exit"
    printf '}\n'
  } > "$receipt"
  echo "Wrote $receipt"
}

TARGET_REPO="$REPO_ROOT"
if [[ "${MAC_GAMP5_USE_CLONE:-1}" == "1" ]]; then
  TARGET_REPO="$CLONE_DIR"
fi
export TARGET_REPO RUN_DIR

if ! run_phase "owner_consent" owner_consent_gate; then
  write_receipt 2 "$TARGET_REPO"
  exit 2
fi
if [[ "${MAC_GAMP5_USE_CLONE:-1}" == "1" ]]; then
  if ! run_phase "clone_or_update" clone_or_update; then
    write_receipt 3 "$TARGET_REPO"
    exit 3
  fi
fi
if ! run_phase "build_launch_macfranklin" build_and_launch_macfranklin "$TARGET_REPO"; then
  write_receipt 4 "$TARGET_REPO"
  exit 4
fi
if ! run_phase "wait_for_runtime_state" wait_for_runtime_state "$TARGET_REPO"; then
  write_receipt 5 "$TARGET_REPO"
  exit 5
fi
if ! run_phase "run_core_games" run_core_games "$TARGET_REPO"; then
  write_receipt 6 "$TARGET_REPO"
  exit 6
fi
if ! run_phase "run_mcp_observer_games" run_mcp_observer_games "$TARGET_REPO"; then
  write_receipt 7 "$TARGET_REPO"
  exit 7
fi

write_receipt 0 "$TARGET_REPO"
echo "PASS: Mac GAMP5 external loop complete. Evidence: $RUN_DIR"
