#!/usr/bin/env zsh
set -euo pipefail

# Franklin full orchestration entrypoint.
# Runs deterministic steps in order unless explicitly skipped.
#
# Default pipeline:
#   1) self-heal preflight
#   2) required asset gate
#   3) Franklin Swift tests
#   4) Franklin app bundle build
#
# Optional:
#   --run      launch built app bundle
#   --run-test launch app binary and verify runtime evidence
#   --sprout   run full sprout A→J flow (requires keys/env)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRANKLIN_ROOT="${ROOT}/GAIAOS/macos/Franklin"
BUILD_SCRIPT="${FRANKLIN_ROOT}/scripts/build_franklin_app_bundle.sh"
SELF_HEAL_SCRIPT="${ROOT}/scripts/self_heal_franklin_fsd_preflight.sh"
ASSET_GATE_SCRIPT="${ROOT}/scripts/check_franklin_avatar_assets.zsh"
SPROUT_SCRIPT="${ROOT}/cells/franklin/avatar/scripts/sprout.zsh"

DO_SELF_HEAL=1
DO_ASSET_GATE=1
DO_TESTS=1
DO_BUILD=1
DO_RUN=0
DO_RUN_TEST=0
DO_UI_PROOF=0
DO_SPROUT=0

RED=$'\033[0;31m'
GRN=$'\033[0;32m'
YLW=$'\033[1;33m'
CYN=$'\033[0;36m'
NC=$'\033[0m'

usage() {
  print "Usage: zsh scripts/program_franklin_app.zsh [options]"
  print ""
  print "Options:"
  print "  --run                 Launch FranklinApp.app after build"
  print "  --run-test            Run FranklinApp binary and assert iq/visible.json"
  print "  --ui-proof            Launch visible app UI and capture screenshot evidence"
  print "  --sprout              Run cells/franklin/avatar/scripts/sprout.zsh after build"
  print "  --skip-self-heal      Skip scripts/self_heal_franklin_fsd_preflight.sh"
  print "  --skip-assets         Skip scripts/check_franklin_avatar_assets.zsh"
  print "  --skip-tests          Skip swift test"
  print "  --skip-build          Skip app bundle build"
  print "  --only-sprout         Run sprout only"
  print "  -h, --help            Show this help"
}

say() {
  print "${CYN}[$(date -u +%Y-%m-%dT%H:%M:%SZ)]${NC} $*"
}

pass() {
  print "${GRN}PASS${NC} $*"
}

refuse() {
  print -u2 "${RED}REFUSED${NC} $*"
  exit 1
}

require_file() {
  local p="$1"
  [[ -f "${p}" ]] || refuse "missing required script: ${p}"
}

while (( $# > 0 )); do
  case "$1" in
    --run) DO_RUN=1 ;;
    --run-test) DO_RUN_TEST=1 ;;
    --ui-proof) DO_UI_PROOF=1 ;;
    --sprout) DO_SPROUT=1 ;;
    --skip-self-heal) DO_SELF_HEAL=0 ;;
    --skip-assets) DO_ASSET_GATE=0 ;;
    --skip-tests) DO_TESTS=0 ;;
    --skip-build) DO_BUILD=0 ;;
    --only-sprout)
      DO_SELF_HEAL=0
      DO_ASSET_GATE=0
      DO_TESTS=0
      DO_BUILD=0
      DO_SPROUT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      refuse "unknown option: $1 (use --help)"
      ;;
  esac
  shift
done

require_file "${SELF_HEAL_SCRIPT}"
require_file "${ASSET_GATE_SCRIPT}"
require_file "${BUILD_SCRIPT}"
require_file "${SPROUT_SCRIPT}"
[[ -d "${FRANKLIN_ROOT}" ]] || refuse "Franklin package path missing: ${FRANKLIN_ROOT}"

say "Franklin pipeline start (root=${ROOT})"

if (( DO_SELF_HEAL )); then
  say "Step 1/4: self-heal preflight"
  zsh "${SELF_HEAL_SCRIPT}" "${ROOT}"
  pass "self-heal preflight complete"
else
  print "${YLW}SKIP${NC} self-heal preflight"
fi

if (( DO_ASSET_GATE )); then
  say "Step 2/4: Franklin asset gate"
  zsh "${ASSET_GATE_SCRIPT}" "${ROOT}"
  pass "asset gate complete"
else
  print "${YLW}SKIP${NC} asset gate"
fi

if (( DO_TESTS )); then
  say "Step 3/4: Franklin Swift unit tests"
  swift test --package-path "${FRANKLIN_ROOT}"
  pass "swift tests complete"
else
  print "${YLW}SKIP${NC} swift tests"
fi

if (( DO_BUILD )); then
  say "Step 4/4: Franklin app bundle build"
  zsh "${BUILD_SCRIPT}"
  pass "app bundle build complete"
else
  print "${YLW}SKIP${NC} app bundle build"
fi

APP_PATH="${FRANKLIN_ROOT}/dist/FranklinApp.app"
APP_BIN="${APP_PATH}/Contents/MacOS/FranklinApp"
if (( DO_RUN )); then
  [[ -d "${APP_PATH}" ]] || refuse "cannot run: app bundle missing (${APP_PATH})"
  say "Launching Franklin app bundle"
  open "${APP_PATH}"
  pass "launch command sent"
fi

if (( DO_RUN_TEST )); then
  [[ -x "${APP_BIN}" ]] || refuse "cannot run-test: app binary missing (${APP_BIN})"
  local_tau="$(date -u +%Y%m%dT%H%M%SZ)"
  evidence_root="${ROOT}/runtime/local-run/${local_tau}/evidence"
  mkdir -p "${evidence_root}/iq" "${evidence_root}/oq" "${evidence_root}/pq"
  run_log="${ROOT}/runtime/local-run/${local_tau}/franklin_app.log"

  say "Launching Franklin binary for runtime evidence test"
  (
    export FRANKLIN_AVATAR_EVIDENCE="${evidence_root}"
    export FRANKLIN_AVATAR_BUNDLE="${ROOT}/cells/franklin/avatar/build/avatar_bundle"
    export FOT_SPROUT_TAU="${local_tau}"
    "${APP_BIN}" >> "${run_log}" 2>&1
  ) &
  app_pid=$!

  visible="${evidence_root}/iq/visible.json"
  deadline=$(( $(date +%s) + 45 ))
  while [[ ! -f "${visible}" ]]; do
    if ! kill -0 "${app_pid}" 2>/dev/null; then
      refuse "run-test failed: Franklin app exited early (log: ${run_log})"
    fi
    if (( $(date +%s) > deadline )); then
      kill "${app_pid}" 2>/dev/null || true
      refuse "run-test timed out waiting for ${visible} (log: ${run_log})"
    fi
    sleep 1
  done

  if ! jq -e '.avatar_mode == "lifelike_3d_runtime"' "${visible}" >/dev/null 2>&1; then
    kill "${app_pid}" 2>/dev/null || true
    refuse "run-test failed: visible.json missing lifelike_3d_runtime"
  fi

  if ! jq -e '.avatar_controls | index("chat") and index("audio") and index("visual") and index("recording")' "${visible}" >/dev/null 2>&1; then
    kill "${app_pid}" 2>/dev/null || true
    refuse "run-test failed: visible.json missing avatar control contract"
  fi

  kill "${app_pid}" 2>/dev/null || true
  pass "run-test complete (evidence: ${visible})"
fi

if (( DO_UI_PROOF )); then
  [[ -d "${APP_PATH}" ]] || refuse "cannot ui-proof: app bundle missing (${APP_PATH})"
  local_tau_ui="$(date -u +%Y%m%dT%H%M%SZ)"
  ui_root="${ROOT}/runtime/local-run/${local_tau_ui}"
  mkdir -p "${ui_root}"
  ui_shot="${ui_root}/ui-proof.png"
  ui_json="${ui_root}/ui-proof.json"

  say "Launching Franklin app UI for visible proof"
  open -a "${APP_PATH}"

  # Verify a real visible window exists for FranklinApp.
  ui_deadline=$(( $(date +%s) + 30 ))
  window_count=0
  while (( $(date +%s) <= ui_deadline )); do
    window_count="$(osascript -e 'tell application "System Events" to tell process "FranklinApp" to count windows' 2>/dev/null || print 0)"
    [[ "${window_count}" =~ '^[0-9]+$' ]] || window_count=0
    if (( window_count > 0 )); then
      break
    fi
    sleep 1
  done
  (( window_count > 0 )) || refuse "ui-proof failed: FranklinApp window not visible within timeout"

  # Persist visible-window metadata proof.
  window_names="$(osascript -e 'tell application "System Events" to tell process "FranklinApp" to get name of every window' 2>/dev/null || print "")"
  cat > "${ui_json}" <<EOF
{"app":"FranklinApp","window_count":${window_count},"window_names":"${window_names//\"/\\\"}","ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

  # Capture current screen as proof artifact.
  if ! screencapture -x "${ui_shot}"; then
    refuse "ui-proof failed: screenshot denied by macOS Screen Recording permissions; grant Terminal/Cursor screen recording and re-run --ui-proof"
  fi
  [[ -f "${ui_shot}" ]] || refuse "ui-proof failed: screenshot missing (${ui_shot})"
  pass "ui-proof complete (window_count=${window_count}, screenshot=${ui_shot}, metadata=${ui_json})"
fi

if (( DO_SPROUT )); then
  [[ -n "${FRANKLIN_KEY:-}" && -f "${FRANKLIN_KEY:-}" ]] || refuse "FRANKLIN_KEY missing or unreadable"
  [[ -n "${FRANKLIN_OPERATOR_KEY:-}" && -f "${FRANKLIN_OPERATOR_KEY:-}" ]] || refuse "FRANKLIN_OPERATOR_KEY missing or unreadable"
  [[ "${FOT_AVATAR_PQ_VISIBLE_OPERATOR_PRESENT:-0}" == "1" ]] || refuse "FOT_AVATAR_PQ_VISIBLE_OPERATOR_PRESENT must equal 1"
  say "Running sprout A→J"
  zsh "${SPROUT_SCRIPT}"
  pass "sprout flow complete"
fi

say "Franklin pipeline finished"
