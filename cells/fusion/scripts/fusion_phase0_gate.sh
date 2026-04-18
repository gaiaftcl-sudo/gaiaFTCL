#!/usr/bin/env bash
# Phase 0 full-stack gate — evidence/fusion_control/phase0_gate/REPORT.json (plan §Phase 0 tracks A–G; schema v2).
#
# Env:
#   FUSION_PHASE0_E2E=1              — run Playwright fusion e2e (Track E2)
#   FUSION_PHASE0_SOAK=1             — fusion_soak_report.sh (E3)
#   FUSION_PHASE0_LONG_RUN_LINES=N   — tail witness file (E4)
#   FUSION_PHASE0_RUN_HEARTBEAT=1    — run fusion_mesh_mooring_heartbeat.sh for C1 (needs NATS + nats CLI)
#   FUSION_PHASE0_NEGATIVE_TEST=1    — force D2 rename test (destructive but restored)
#   FUSION_PHASE0_SKIP_NEGATIVE=1    — skip D2 (marks Phase 0 NOT fully green — plan requires D2 for Track D)
#   FUSION_PHASE0_SKIP_TRACK_F=1     — skip API curls (CI without dev server)
#   FUSION_UI_PORT                   — default 8910 for Track F
#   FUSION_PHASE0_DISCORD_RECEIPT    — path to G1 evidence file; default checks steps/discord_slash_receipt.md
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
OUT_DIR="$ROOT/evidence/fusion_control/phase0_gate"
STEPS_DIR="$OUT_DIR/steps"
REPORT="$OUT_DIR/REPORT.json"
UI="$ROOT/services/gaiaos_ui_web"
LONG_RUN="$ROOT/evidence/fusion_control/long_run_signals.jsonl"
LONG_WITNESS_FILE="$STEPS_DIR/E_E4_long_run_tail.txt"
UI_PORT="${FUSION_UI_PORT:-8910}"
UI_BASE="http://127.0.0.1:${UI_PORT}"

GAIA_DIR="${HOME}/.gaiaftcl"
IDENT="${GAIA_DIR}/cell_identity.json"
MOUNT="${GAIA_DIR}/mount_receipt.json"
MOOR_STATE="${FUSION_MOORING_STATE_JSON:-${GAIA_DIR}/fusion_mesh_mooring_state.json}"
PROJ="${FUSION_PROJECTION_JSON:-$ROOT/deploy/fusion_mesh/fusion_projection.json}"
HEARTBEAT_SH="$ROOT/deploy/mac_cell_mount/bin/fusion_mesh_mooring_heartbeat.sh"

mkdir -p "$STEPS_DIR"

STEPS_JSON='[]'
FAILED=0

D2_BAK="${IDENT}.bak.phase0_gate"
restore_cell_identity() {
  if [[ -f "$D2_BAK" ]] && [[ ! -f "$IDENT" ]]; then
    mv "$D2_BAK" "$IDENT" 2>/dev/null || true
  fi
}
trap restore_cell_identity EXIT

# Append one step object to STEPS_JSON; status: passed | failed | skipped
step_record() {
  local track="$1" step="$2" status="$3" exit_code="$4" log_rel="$5" note="$6"
  STEPS_JSON=$(echo "$STEPS_JSON" | jq -c \
    --arg track "$track" \
    --arg step "$step" \
    --arg status "$status" \
    --arg ec_raw "${exit_code:-}" \
    --arg log "$log_rel" \
    --arg note "$note" \
    '. + [{
      track: $track, step: $step, status: $status,
      exit_code: (if ($ec_raw | length) == 0 or $ec_raw == "null" then null else (try ($ec_raw | tonumber) catch null) end),
      log: $log, note: $note
    }]')
  if [[ "$status" == "failed" ]]; then
    FAILED=1
  fi
}

GIT_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Track A ---
set +e
bash "$ROOT/scripts/scope_fortress_scan.sh" >"$STEPS_DIR/A_A1_scope_fortress.log" 2>&1
a_ec=$?
set -e
if [[ "$a_ec" -eq 0 ]]; then
  step_record "A" "A1" "passed" "$a_ec" "${STEPS_DIR#$ROOT/}/A_A1_scope_fortress.log" "scope_fortress_scan.sh"
else
  step_record "A" "A1" "failed" "$a_ec" "${STEPS_DIR#$ROOT/}/A_A1_scope_fortress.log" "scope_fortress_scan.sh"
fi

# --- Track B ---
if [[ -f "$IDENT" ]]; then
  cp -f "$IDENT" "$OUT_DIR/cell_identity.json.snapshot" 2>/dev/null || true
  step_record "B" "B1" "passed" 0 "" "cell_identity.json present; snapshot copied if writable"
  cid="$(jq -r '.cell_id // empty' "$IDENT" 2>/dev/null || echo "")"
  if [[ -n "$cid" ]] && [[ "$cid" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    step_record "B" "B2" "passed" 0 "" "cell_id valid: $cid"
  else
    step_record "B" "B2" "failed" 1 "" "cell_id missing or invalid pattern"
  fi
else
  step_record "B" "B1" "failed" 1 "" "missing $IDENT"
  step_record "B" "B2" "skipped" null "" "skipped — no cell_identity"
fi

if [[ -f "$MOUNT" ]]; then
  cp -f "$MOUNT" "$OUT_DIR/mount_receipt.json.snapshot" 2>/dev/null || true
  step_record "B" "B3" "passed" 0 "" "mount_receipt.json present"
else
  step_record "B" "B3" "failed" 1 "" "missing $MOUNT"
fi

# --- Track C ---
if [[ "${FUSION_PHASE0_RUN_HEARTBEAT:-0}" == "1" ]]; then
  set +e
  bash "$HEARTBEAT_SH" >"$STEPS_DIR/C_C1_heartbeat.log" 2>&1
  c1_ec=$?
  set -e
  if [[ "$c1_ec" -eq 0 ]]; then
    step_record "C" "C1" "passed" "$c1_ec" "${STEPS_DIR#$ROOT/}/C_C1_heartbeat.log" "fusion_mesh_mooring_heartbeat.sh"
  else
    step_record "C" "C1" "failed" "$c1_ec" "${STEPS_DIR#$ROOT/}/C_C1_heartbeat.log" "heartbeat script failed"
  fi
elif [[ -f "$MOOR_STATE" ]]; then
  step_record "C" "C1" "passed" 0 "" "moor state file present (set FUSION_PHASE0_RUN_HEARTBEAT=1 to require wire publish)"
else
  step_record "C" "C1" "failed" 1 "" "missing $MOOR_STATE — run heartbeat or FUSION_PHASE0_RUN_HEARTBEAT=1"
fi

if [[ -f "$MOOR_STATE" ]]; then
  cp -f "$MOOR_STATE" "$OUT_DIR/fusion_mesh_mooring_state.json.snapshot" 2>/dev/null || true
  sch="$(jq -r '.schema // empty' "$MOOR_STATE" 2>/dev/null || echo "")"
  last="$(jq -r '.last_mesh_ok_utc // empty' "$MOOR_STATE" 2>/dev/null || echo "")"
  mid="$(jq -r '.cell_id // empty' "$MOOR_STATE" 2>/dev/null || true)"
  id_expect="$(jq -r '.cell_id // empty' "$IDENT" 2>/dev/null || echo "")"
  if [[ "$sch" == "gaiaftcl_fusion_mooring_state_v1" ]] && [[ -n "$last" ]] && python3 -c "import datetime; datetime.datetime.fromisoformat('${last}'.replace('Z','+00:00'))" 2>/dev/null; then
    if [[ -f "$IDENT" ]] && [[ -n "$id_expect" ]]; then
      if [[ "$mid" != "$id_expect" ]]; then
        step_record "C" "C2" "failed" 1 "" "moor cell_id mismatch identity: moor=$mid identity=$id_expect"
      else
        step_record "C" "C2" "passed" 0 "" "schema + last_mesh_ok_utc + cell_id matches identity"
      fi
    else
      step_record "C" "C2" "passed" 0 "" "schema + last_mesh_ok_utc valid (no identity file to cross-check)"
    fi
  else
    step_record "C" "C2" "failed" 1 "" "schema or last_mesh_ok_utc invalid"
  fi
else
  step_record "C" "C2" "skipped" null "" "no moor state file"
fi

if [[ -f "$MOOR_STATE" ]] && [[ -f "$PROJ" ]]; then
  max_sec="$(jq -r '.payment_projection.mesh_heartbeat_max_sec // 86400' "$PROJ")"
  last="$(jq -r '.last_mesh_ok_utc // empty' "$MOOR_STATE")"
  if [[ -n "$last" ]]; then
    age_sec="$(python3 -c "
import datetime, sys
s = sys.argv[1]
d = datetime.datetime.fromisoformat(s.replace('Z', '+00:00'))
now = datetime.datetime.now(datetime.timezone.utc)
print(int((now - d.astimezone(datetime.timezone.utc)).total_seconds()))
" "$last")"
    if [[ "$age_sec" -le "$max_sec" ]]; then
      step_record "C" "C3" "passed" 0 "" "age_sec=$age_sec max_sec=$max_sec"
    else
      step_record "C" "C3" "failed" 1 "" "stale heartbeat age_sec=$age_sec max_sec=$max_sec"
    fi
  else
    step_record "C" "C3" "failed" 1 "" "no last_mesh_ok_utc"
  fi
else
  step_record "C" "C3" "skipped" null "" "missing moor or projection"
fi

# --- Track D ---
set +e
bash "$ROOT/scripts/fusion_moor_preflight.sh" >"$STEPS_DIR/D_D1_preflight.log" 2>&1
d1_ec=$?
set -e
if [[ "$d1_ec" -eq 0 ]]; then
  step_record "D" "D1" "passed" "$d1_ec" "${STEPS_DIR#$ROOT/}/D_D1_preflight.log" "fusion_moor_preflight.sh"
else
  step_record "D" "D1" "failed" "$d1_ec" "${STEPS_DIR#$ROOT/}/D_D1_preflight.log" "fusion_moor_preflight.sh"
fi

D2_RAN=0
if [[ "${FUSION_PHASE0_SKIP_NEGATIVE:-0}" == "1" ]]; then
  step_record "D" "D2" "failed" null "" "SKIPPED by FUSION_PHASE0_SKIP_NEGATIVE=1 — plan requires D2 for full green"
  FAILED=1
elif [[ ! -f "$IDENT" ]]; then
  step_record "D" "D2" "skipped" null "" "no cell_identity — cannot run negative test"
  FAILED=1
elif [[ "${FUSION_PHASE0_NEGATIVE_TEST:-1}" == "1" ]]; then
  D2_RAN=1
  rm -f "$D2_BAK"
  mv "$IDENT" "$D2_BAK"
  set +e
  bash "$ROOT/scripts/fusion_moor_preflight.sh" >"$STEPS_DIR/D_D2_negative.log" 2>&1
  d2_ec=$?
  set -e
  mv "$D2_BAK" "$IDENT"
  if [[ "$d2_ec" -ne 0 ]] && grep -q cell_identity "$STEPS_DIR/D_D2_negative.log" 2>/dev/null; then
    step_record "D" "D2" "passed" "$d2_ec" "${STEPS_DIR#$ROOT/}/D_D2_negative.log" "preflight refused on missing identity as expected"
  else
    step_record "D" "D2" "failed" "$d2_ec" "${STEPS_DIR#$ROOT/}/D_D2_negative.log" "expected non-zero exit + stderr mentioning cell_identity"
    FAILED=1
  fi
else
  step_record "D" "D2" "failed" null "" "set FUSION_PHASE0_NEGATIVE_TEST=1 or unset skip — D2 required for full green"
  FAILED=1
fi

if [[ "$D2_RAN" -eq 1 ]]; then
  step_record "D" "D3" "passed" 0 "" "cell_identity restored after D2"
else
  step_record "D" "D3" "skipped" null "" "D2 not run — no restore needed"
fi

# --- Track E ---
set +e
bash "$ROOT/scripts/preflight_fusion_ui_live.sh" >"$STEPS_DIR/E_E1_fusion_ui_preflight.log" 2>&1
e1_ec=$?
set -e
if [[ "$e1_ec" -eq 0 ]]; then
  step_record "E" "E1" "passed" "$e1_ec" "${STEPS_DIR#$ROOT/}/E_E1_fusion_ui_preflight.log" "preflight_fusion_ui_live.sh"
else
  step_record "E" "E1" "failed" "$e1_ec" "${STEPS_DIR#$ROOT/}/E_E1_fusion_ui_preflight.log" "preflight_fusion_ui_live.sh"
fi

if [[ "${FUSION_PHASE0_E2E:-0}" == "1" ]]; then
  set +e
  bash -c "cd \"$UI\" && GAIA_ROOT=\"$ROOT\" npm run test:e2e:fusion" >"$STEPS_DIR/E_E2_playwright.log" 2>&1
  e2_ec=$?
  set -e
  if [[ "$e2_ec" -eq 0 ]]; then
    step_record "E" "E2" "passed" "$e2_ec" "${STEPS_DIR#$ROOT/}/E_E2_playwright.log" "npm run test:e2e:fusion"
  else
    step_record "E" "E2" "failed" "$e2_ec" "${STEPS_DIR#$ROOT/}/E_E2_playwright.log" "npm run test:e2e:fusion"
  fi
else
  step_record "E" "E2" "skipped" null "" "set FUSION_PHASE0_E2E=1 to run Playwright"
fi

if [[ "${FUSION_PHASE0_SOAK:-0}" == "1" ]]; then
  set +e
  bash "$ROOT/scripts/fusion_soak_report.sh" >"$STEPS_DIR/E_E3_soak.log" 2>&1
  e3_ec=$?
  set -e
  if [[ "$e3_ec" -eq 0 ]]; then
    step_record "E" "E3" "passed" "$e3_ec" "${STEPS_DIR#$ROOT/}/E_E3_soak.log" "fusion_soak_report.sh"
  else
    step_record "E" "E3" "failed" "$e3_ec" "${STEPS_DIR#$ROOT/}/E_E3_soak.log" "fusion_soak_report.sh"
  fi
else
  step_record "E" "E3" "skipped" null "" "set FUSION_PHASE0_SOAK=1 for soak report"
fi

LONG_REF=""
if [[ "${FUSION_PHASE0_LONG_RUN_LINES:-0}" =~ ^[0-9]+$ ]] && [[ "${FUSION_PHASE0_LONG_RUN_LINES:-0}" -gt 0 ]]; then
  if [[ -f "$LONG_RUN" ]]; then
    tail -n "${FUSION_PHASE0_LONG_RUN_LINES}" "$LONG_RUN" >"$LONG_WITNESS_FILE" 2>/dev/null || true
    LONG_REF="${LONG_WITNESS_FILE#$ROOT/}"
    step_record "E" "E4" "passed" 0 "$LONG_REF" "long_run tail witness"
  else
    echo "(missing $LONG_RUN)" >"$LONG_WITNESS_FILE"
    LONG_REF="${LONG_WITNESS_FILE#$ROOT/}"
    step_record "E" "E4" "failed" 1 "$LONG_REF" "long_run_signals.jsonl missing"
    FAILED=1
  fi
else
  step_record "E" "E4" "skipped" null "" "set FUSION_PHASE0_LONG_RUN_LINES=N for tail witness"
fi

# --- Track F ---
if [[ "${FUSION_PHASE0_SKIP_TRACK_F:-0}" == "1" ]]; then
  step_record "F" "F1" "skipped" null "" "FUSION_PHASE0_SKIP_TRACK_F=1"
  step_record "F" "F2" "skipped" null "" "FUSION_PHASE0_SKIP_TRACK_F=1"
  step_record "F" "F3" "skipped" null "" "FUSION_PHASE0_SKIP_TRACK_F=1"
  FAILED=1
else
  if command -v curl >/dev/null 2>&1; then
    set +e
    curl -sf "$UI_BASE/api/fusion/fleet-digest" >"$STEPS_DIR/F_F1_fleet_digest_response.json" 2>"$STEPS_DIR/F_F1_curl.err"
    f1=$?
    set -e
    if [[ "$f1" -eq 0 ]]; then
      step_record "F" "F1" "passed" 0 "${STEPS_DIR#$ROOT/}/F_F1_fleet_digest_response.json" "fleet-digest"
    else
      step_record "F" "F1" "failed" "$f1" "${STEPS_DIR#$ROOT/}/F_F1_curl.err" "curl fleet-digest (start UI: npm run dev:fusion)"
      FAILED=1
    fi
    set +e
    curl -sf "$UI_BASE/api/fusion/fleet-usd" >"$STEPS_DIR/F_F2_fleet_usd_response.usda" 2>"$STEPS_DIR/F_F2_curl.err"
    f2=$?
    set -e
    if [[ "$f2" -eq 0 ]] && head -1 "$STEPS_DIR/F_F2_fleet_usd_response.usda" | grep -q '#usda'; then
      step_record "F" "F2" "passed" 0 "${STEPS_DIR#$ROOT/}/F_F2_fleet_usd_response.usda" "fleet-usd"
    else
      step_record "F" "F2" "failed" "${f2:-1}" "${STEPS_DIR#$ROOT/}/F_F2_curl.err" "fleet-usd missing #usda or curl failed"
      FAILED=1
    fi
    set +e
    curl -sf "$UI_BASE/api/fusion/s4-projection" >"$STEPS_DIR/F_F3_s4_projection_response.json" 2>"$STEPS_DIR/F_F3_curl.err"
    f3=$?
    set -e
    if [[ "$f3" -eq 0 ]]; then
      step_record "F" "F3" "passed" 0 "${STEPS_DIR#$ROOT/}/F_F3_s4_projection_response.json" "s4-projection"
    else
      step_record "F" "F3" "failed" "$f3" "${STEPS_DIR#$ROOT/}/F_F3_curl.err" "s4-projection"
      FAILED=1
    fi
  else
    step_record "F" "F1" "failed" 1 "" "curl not installed"
    step_record "F" "F2" "failed" 1 "" "curl not installed"
    step_record "F" "F3" "failed" 1 "" "curl not installed"
    FAILED=1
  fi
fi

# --- Track G ---
G_RECEIPT="${FUSION_PHASE0_DISCORD_RECEIPT:-$STEPS_DIR/discord_slash_receipt.md}"
if [[ -f "$G_RECEIPT" ]]; then
  step_record "G" "G1" "passed" 0 "${G_RECEIPT#$ROOT/}" "discord slash receipt present"
else
  step_record "G" "G1" "skipped" null "" "manual: run /fusion_fleet in Discord; save evidence to $G_RECEIPT (does not block per plan)"
fi

jq -n \
  --arg utc "$UTC" \
  --arg root "$ROOT" \
  --arg sha "$GIT_SHA" \
  --arg longref "$LONG_REF" \
  --argjson failed "$FAILED" \
  --argjson steps "$STEPS_JSON" \
  '{
    schema: "gaiaftcl_fusion_phase0_gate_report_v2",
    generated_at_utc: $utc,
    GAIA_ROOT: $root,
    git_sha: $sha,
    long_run_tail_witness_path: (if ($longref | length) > 0 then $longref else null end),
    overall_ok: (if $failed == 0 then true else false end),
    steps: $steps
  }' >"$REPORT"

echo "[fusion_phase0_gate] wrote $REPORT (schema v2, tracks A–G)"

if [[ "$FAILED" -ne 0 ]]; then
  echo "REFUSED: phase0_gate — see $REPORT" >&2
  exit 1
fi

echo "CALORIE: phase0_gate green"
exit 0
