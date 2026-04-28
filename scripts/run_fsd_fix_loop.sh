#!/usr/bin/env zsh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
OUT_DIR="${ROOT}/evidence/fsd_fix_loop"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
RECEIPT="${OUT_DIR}/fsd_fix_loop_receipt_${TS}.json"

mkdir -p "${OUT_DIR}"

typeset -a STEP_NAMES=()
typeset -a STEP_STATUS=()
typeset -a STEP_RC=()

run_step() {
  local name="$1"
  shift
  local rc=0
  if "$@" > "${OUT_DIR}/${TS}_${name}.log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  STEP_NAMES+=("${name}")
  STEP_RC+=("${rc}")
  if (( rc == 0 )); then
    STEP_STATUS+=("PASS")
  else
    STEP_STATUS+=("FAIL")
  fi
}

cd "${ROOT}"

run_step "inventory" zsh "scripts/generate_fsd_missing_refs.sh" "${ROOT}" "${OUT_DIR}/missing_refs_${TS}.json"
run_step "mac_stack_tsd" zsh "scripts/validate_mac_cell_stacks_tsd.sh" "${ROOT}"
run_step "franklin_pins" python3 "cells/franklin/scripts/verify_franklin_pins.py"
run_step "health_gamp5" bash "cells/health/scripts/health_cell_gamp5_validate.sh"

overall="PASS"
for rc in "${STEP_RC[@]}"; do
  if (( rc != 0 )); then
    overall="FAIL"
    break
  fi
done

{
  print "{"
  print "  \"timestamp\": \"${TS}\","
  print "  \"overall\": \"${overall}\","
  print "  \"steps\": ["
  local i=1
  local total="${#STEP_NAMES[@]}"
  while (( i <= total )); do
    print "    {\"name\":\"${STEP_NAMES[$i]}\",\"status\":\"${STEP_STATUS[$i]}\",\"rc\":${STEP_RC[$i]}}$( (( i < total )) && print , )"
    i=$(( i + 1 ))
  done
  print "  ]"
  print "}"
} > "${RECEIPT}"

cp -f "${RECEIPT}" "${OUT_DIR}/latest.json"
print "RECEIPT:${RECEIPT}"

[[ "${overall}" == "PASS" ]]
