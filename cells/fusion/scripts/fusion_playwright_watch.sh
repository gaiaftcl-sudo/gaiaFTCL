#!/usr/bin/env bash
# Autonomous self-healing Fusion Playwright watchdog.
# Runs two UI validation tracks in each cycle:
#   1) self-heal anchor recovery test
#   2) full fusion Playwright suite
# If a track fails, the loop records failure and immediately retries once.
# Loop continues until stop file is present or optional cycle budget is exhausted.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI_DIR="$ROOT/services/gaiaos_ui_web"
EVID_DIR="$ROOT/evidence/fusion_control/playwright_watch"
export EVID_DIR
mkdir -p "$EVID_DIR"

STATE_FILE="$EVID_DIR/watch_state.json"
PID_FILE="$EVID_DIR/playwright_watch.pid"
LOG_FILE="$EVID_DIR/watch.log"
LAST_WITNESS="$EVID_DIR/playwright_watch_last_witness.json"
STOP_FILE="${FUSION_PLAYWRIGHT_WATCH_STOP_FILE:-$EVID_DIR/STOP}"
INTERVAL="${FUSION_PLAYWRIGHT_INTERVAL_SEC:-900}"
MAX_CYCLES="${FUSION_PLAYWRIGHT_MAX_CYCLES:-0}"
RUN_FULL="${FUSION_PLAYWRIGHT_RUN_FULL:-1}"
RUN_SELF_HEAL="${FUSION_PLAYWRIGHT_RUN_SELF_HEAL:-1}"
TEST_RETRIES="${FUSION_PLAYWRIGHT_TEST_RETRIES:-2}"
PRECOMPILE_METAL="${FUSION_PLAYWRIGHT_PRECOMPILE_METAL:-1}"

SELF_HEAL_TEST="tests/fusion/fusion_s4_console.spec.ts -g \"WASM UI self-heals missing anchors and UI state without external input\""
FULL_TEST_CMD="test:e2e:fusion"

note() {
  printf '%s %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOG_FILE"
}

running() {
  kill -0 "$1" 2>/dev/null
}

assert_singleton() {
  if [[ -f "$PID_FILE" ]]; then
    local old
    old="$(tr -d '[:space:]' <"$PID_FILE" || true)"
    if [[ -n "${old}" ]] && running "$old"; then
      note "REFUSED: existing playwright_watch process already active pid=$old"
      echo "playwright_watch already running pid=$old" >&2
      exit 2
    fi
  fi
  echo "$$" > "$PID_FILE"
}

cleanup() {
  local rc=${1:-$?}
  rm -f "$PID_FILE"
  note "EXIT rc=$rc (pid=$$)"
}
trap 'cleanup $?' EXIT
trap 'note "TRAP INT"; exit 0' INT
trap 'note "TRAP TERM"; exit 0' TERM

emit_witness() {
  local cycle="$1" terminal="$2" self_rc="$3" full_rc="$4" sleep_sec="$5"
  local elapsed="$6" run="false"
  python3 - "$cycle" "$terminal" "$self_rc" "$full_rc" "$sleep_sec" "$elapsed" <<'PY'
import json, os, pathlib, sys
cycle, terminal, self_rc, full_rc, sleep_sec, elapsed = sys.argv[1:7]
payload = {
  "schema": "gaiaftcl_fusion_playwright_watch_v1",
  "ts_utc": __import__("datetime").datetime.utcnow().isoformat() + "Z",
  "terminal": terminal,
  "cycle": int(cycle),
  "self_heal_rc": int(self_rc),
  "full_suite_rc": int(full_rc),
  "interval_sec": int(sleep_sec),
  "test_path": {
    "self_heal": "tests/fusion/fusion_s4_console.spec.ts -g \"WASM UI self-heals missing anchors and UI state without external input\"",
    "full_suite": "test:e2e:fusion",
  },
  "run_full": bool(os.environ.get("FUSION_PLAYWRIGHT_RUN_FULL", "1") == "1"),
  "run_self_heal": bool(os.environ.get("FUSION_PLAYWRIGHT_RUN_SELF_HEAL", "1") == "1"),
  "elapsed_total_sec": float(elapsed),
  "track": "FOT_FIELD_OF_FIELDS",
}
path = os.path.join(os.environ["EVID_DIR"], "playwright_watch_last_witness.json")
pathlib.Path(path).write_text(json.dumps(payload, indent=2), encoding="utf-8")
PY
}

run_once_with_retry() {
  local label="$1"
  shift
  local rc=0
  local attempt=1
  while true; do
    note "START: $label attempt=$attempt"
    set +e
    "$@"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      note "PASS: $label attempt=$attempt"
      return 0
    fi
    if [[ "$attempt" -ge "$TEST_RETRIES" ]]; then
      note "FAIL: $label attempt=$attempt rc=$rc"
      return "$rc"
    fi
    attempt=$((attempt + 1))
    note "RETRY: $label rc=$rc, re-run in 10s (attempt $attempt)"
    sleep 10
  done
}

run_self_heal_test() {
  if [[ "${RUN_SELF_HEAL}" != "1" ]]; then
    note "SKIP: self-heal track disabled"
    return 0
  fi
  run_once_with_retry "WASM self-heal" bash -lc "cd \"${UI_DIR}\" && GAIA_ROOT=\"${ROOT}\" npm run test:e2e:fusion -- ${SELF_HEAL_TEST}"
}

run_full_test() {
  if [[ "${RUN_FULL}" != "1" ]]; then
    note "SKIP: full suite disabled"
    return 0
  fi
  run_once_with_retry "Fusion full suite" bash -lc "cd \"${UI_DIR}\" && GAIA_ROOT=\"${ROOT}\" npm run ${FULL_TEST_CMD}"
}

run_precompile_once() {
  if [[ "${PRECOMPILE_METAL}" != "1" ]]; then
    return 0
  fi
  note "START precompile: build_metal_lib"
  if bash "$ROOT/scripts/build_metal_lib.sh" >>"$LOG_FILE" 2>&1; then
    note "PASS precompile: build_metal_lib"
    return 0
  fi
  note "REFUSED precompile: build_metal_lib failed (continuing)"
  return 1
}

get_cycle_start() {
  if [[ -f "$STATE_FILE" ]]; then
    python3 - "$STATE_FILE" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("next_cycle", 1))
PY
    return
  fi
  echo 1
}

assert_singleton
note "START playwright_watch ROOT=$ROOT pid=$$ interval=${INTERVAL}s max_cycles=${MAX_CYCLES}"

if ! run_precompile_once; then
  note "WARN: precompile failed; watchdog will continue without fresh metal lib refresh"
fi

cycle="$(get_cycle_start)"
if [[ -z "${cycle}" || "${cycle}" == "None" ]]; then
  cycle=1
fi

while true; do
  if [[ -f "$STOP_FILE" ]]; then
    note "STOP: stop-file seen $STOP_FILE"
    break
  fi
  if [[ "$MAX_CYCLES" -gt 0 && "$cycle" -gt "$MAX_CYCLES" ]]; then
    note "STOP: max_cycles=$MAX_CYCLES reached"
    break
  fi

  start_ts="$(date +%s)"
  cstart="$(date -Iseconds)"
  note "CYCLE_START $cycle on $cstart"

  self_rc=0
  full_rc=0

  run_self_heal_test || self_rc=$?
  run_full_test || full_rc=$?

  elapsed="$(( $(date +%s) - start_ts ))"
  if [[ "$self_rc" -eq 0 && "$full_rc" -eq 0 ]]; then
    terminal="CURE"
    note "CYCLE_PASS cycle=$cycle terminal=$terminal self_rc=$self_rc full_rc=$full_rc elapsed=${elapsed}s"
  else
    terminal="REFUSED"
    note "CYCLE_FAIL cycle=$cycle terminal=$terminal self_rc=$self_rc full_rc=$full_rc elapsed=${elapsed}s"
  fi

  emit_witness "$cycle" "$terminal" "$self_rc" "$full_rc" "$INTERVAL" "$elapsed"
  python3 - "$STATE_FILE" "$cycle" "$self_rc" "$full_rc" "$terminal" <<'PY'
import json, os, sys
state = {
  "next_cycle": int(sys.argv[2]) + 1,
  "ts_utc": __import__("datetime").datetime.utcnow().isoformat() + "Z",
  "self_heal_rc": int(sys.argv[3]),
  "full_suite_rc": int(sys.argv[4]),
  "terminal": sys.argv[5],
}
path = sys.argv[1]
with open(path, "w", encoding="utf-8") as f:
  json.dump(state, f, indent=2)
PY

  cycle=$((cycle + 1))
  if [[ "$MAX_CYCLES" -gt 0 && "$cycle" -gt "$MAX_CYCLES" ]]; then
    note "DONE: max_cycles reached"
    break
  fi
  note "SLEEP cycle=$((cycle - 1)) interval=${INTERVAL}"
  sleep "$INTERVAL"
done

