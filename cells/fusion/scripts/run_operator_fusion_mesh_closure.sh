#!/usr/bin/env bash
# Cell-Operator — fusion + mesh closure spine (single process, one exit code, no chat between phases).
# Run this instead of looping "continue" in the IDE. Receipt + log under evidence/fusion_control/.
#
# Phases (order is fixed; any failure stops with REFUSED and non-zero exit):
#   1  verify_plant_adapters_contract.sh
#   2  verify_fusion_sidecar_bundle.sh
#   3  invariant_mesh_green_probe.sh  (nine-cell :8803 /health)
#   4  Mac :8803 convergence (Darwin): curl /health → if not 2xx, open GaiaFusion.app and retry → mcp_mac_cell_probe.py
#   5  fusion_ui_self_heal_loop.py  (MCP conversation + deterministic self-heal ladder)
#   6  verify_gaiafusion_working_app.sh  (composite gate → self-probe → static → mac + WAN mesh)
#
# Env:
#   OPERATOR_CLOSURE_SKIP_WORKING_APP=1   — run phases 1–4 only (no Playwright/GaiaFusion gate; faster CI/sanity)
#   FUSION_UI_SELF_HEAL_RELAX_MAC_GATEWAY=1 — phase 5: in-VM sidecar (no host :8803); exported to fusion_ui_self_heal_loop.py
#   OPERATOR_CLOSURE_SKIP_MAC_PROBE=1     — skip phase 4 (not recommended for Mac production closure)
#   OPERATOR_CLOSURE_MAC_CONVERGE_MAX_RETRIES — default 3 (phase 4 loopback bring-up attempts)
#   OPERATOR_CLOSURE_MAC_CONVERGE_SLEEP_SEC   — default 8 (sleep between attempts after open)
#   GAIAFUSION_OPERATOR_APP_PATH            — if set, `open` this .app bundle instead of `open -a GaiaFusion`
#   OPERATOR_CLOSURE_SKIP_SELF_HEAL_LOOP=0 — set 1 to skip loop phase (not recommended)
#   FUSION_UI_SELF_HEAL_MAX_CYCLES / FUSION_UI_SELF_HEAL_MODE / FUSION_UI_PORT pass through to loop runner
#   GAIA_ROOT                             — repo root (default: parent of scripts/)
#   Phase 6 (`verify_gaiafusion_working_app.sh`) inherits that script’s env (e.g. GAIAFUSION_SKIP_MESH_MCP,
#   GAIAFUSION_SKIP_MAC_CELL_MCP, GAIAFUSION_INCLUDE_XCTEST — XCTest uses swift test --disable-sandbox when enabled).
#
# Host Mac (arm64, non-CI): GAIAFUSION_SKIP_* cleared — scripts/lib/gaiafusion_host_c4_lock.sh
# Override: GAIAFUSION_ALLOW_SKIP_ON_HOST=1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
cd "$ROOT"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/gaiafusion_host_c4_lock.sh"
gaiafusion_host_strip_skip_leak

EV="${ROOT}/evidence/fusion_control"
mkdir -p "$EV"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
TS_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG="${EV}/operator_fusion_mesh_closure_${TS}.log"
RECEIPT="${EV}/operator_fusion_mesh_closure_receipt_${TS}.json"
MAC_TMP="$(mktemp "${TMPDIR:-/tmp}/op_mac_probe.XXXXXX")"
trap 'rm -f "$MAC_TMP"' EXIT

SKIP_APP="${OPERATOR_CLOSURE_SKIP_WORKING_APP:-0}"
SKIP_MAC="${OPERATOR_CLOSURE_SKIP_MAC_PROBE:-0}"
SKIP_LOOP="${OPERATOR_CLOSURE_SKIP_SELF_HEAL_LOOP:-0}"

exec > >(tee -a "$LOG") 2>&1

echo "=== run_operator_fusion_mesh_closure ts=${TS_ISO} GAIA_ROOT=${ROOT} ==="
echo "OPERATOR_CLOSURE_SKIP_WORKING_APP=${SKIP_APP} OPERATOR_CLOSURE_SKIP_MAC_PROBE=${SKIP_MAC} OPERATOR_CLOSURE_SKIP_SELF_HEAL_LOOP=${SKIP_LOOP}"

die() {
  local reason="$*"
  echo "REFUSED: $reason" >&2
  python3 - "$RECEIPT" "$TS_ISO" "${LOG#${ROOT}/}" "$reason" <<'PY'
import json, sys
from pathlib import Path
path, ts, log_rel, reason = sys.argv[1:5]
doc = {
    "schema": "gaiaftcl_operator_fusion_mesh_closure_v1",
    "ts_utc": ts,
    "terminal": "REFUSED",
    "reason": reason,
    "log": log_rel,
}
Path(path).write_text(json.dumps(doc, indent=2), encoding="utf-8")
PY
  exit 1
}

echo "## phase 1 plant_adapters"
bash "${ROOT}/scripts/verify_plant_adapters_contract.sh" || die "phase1 verify_plant_adapters_contract"

echo "## phase 2 fusion_sidecar_bundle"
bash "${ROOT}/scripts/verify_fusion_sidecar_bundle.sh" || die "phase2 verify_fusion_sidecar_bundle"

echo "## phase 3 invariant_mesh_green_probe (nine-cell)"
bash "${ROOT}/scripts/invariant_mesh_green_probe.sh" || die "phase3 invariant_mesh_green_probe"

phase4_status="SKIPPED"
if [[ "$SKIP_MAC" == "1" ]]; then
  phase4_status="SKIPPED_OPERATOR_ENV"
  echo 'null' >"$MAC_TMP"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  echo "## phase 4 mac cell loopback convergence + mcp_mac_cell_probe (127.0.0.1:8803)"
  MAC_HOST="${GAIAFUSION_MAC_CELL_HOST:-127.0.0.1}"
  MAC_PORT="${GAIAFUSION_MAC_CELL_PORT:-8803}"
  MAC_MAX="${OPERATOR_CLOSURE_MAC_CONVERGE_MAX_RETRIES:-3}"
  MAC_SLEEP="${OPERATOR_CLOSURE_MAC_CONVERGE_SLEEP_SEC:-8}"
  APP_BUNDLE="${GAIAFUSION_OPERATOR_APP_PATH:-}"
  health_url="http://${MAC_HOST}:${MAC_PORT}/health"

  mac_health_code() {
    local raw c
    raw="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 12 "${health_url}" 2>/dev/null)" || true
    if [[ -z "$raw" ]]; then
      echo "000"
      return
    fi
    c="$raw"
    if [[ ${#c} -gt 3 ]]; then
      c="${c: -3}"
    fi
    echo "$c"
  }

  HTTP_STATUS="$(mac_health_code)"
  for ((retry = 0; retry < MAC_MAX; retry++)); do
    if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]; then
      echo "phase 4: loopback ${health_url} -> HTTP ${HTTP_STATUS}"
      break
    fi
    echo "phase 4: loopback not ready (HTTP ${HTTP_STATUS}); attempt $((retry + 1))/${MAC_MAX}"
    if [[ "$HTTP_STATUS" == "000" ]]; then
      echo "phase 4: instantiating GaiaFusion (McpLoopbackCommsServer bind on :${MAC_PORT})..."
      if [[ -n "$APP_BUNDLE" ]]; then
        if [[ -d "$APP_BUNDLE" ]]; then
          open "$APP_BUNDLE" || true
        else
          echo "phase 4: GAIAFUSION_OPERATOR_APP_PATH not a directory: ${APP_BUNDLE}" >&2
          open -a "GaiaFusion" || true
        fi
      else
        open -a "GaiaFusion" 2>/dev/null || {
          # Fallback: SwiftPM debug binary's packaged .app path (developer tree).
          sp_app="${ROOT}/macos/GaiaFusion/.build/arm64-apple-macosx/debug/GaiaFusion.app"
          if [[ -d "$sp_app" ]]; then
            open "$sp_app" || true
          else
            echo "phase 4: open -a GaiaFusion failed and no fallback .app at ${sp_app}" >&2
          fi
        }
      fi
    else
      echo "phase 4: listener present but /health not 2xx (${HTTP_STATUS}); waiting for McpLoopbackCommsServer/upstream..."
    fi
    sleep "$MAC_SLEEP"
    HTTP_STATUS="$(mac_health_code)"
  done

  if ! [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]; then
    die "phase4 mac loopback did not converge: ${health_url} last_http=${HTTP_STATUS} (set GAIAFUSION_OPERATOR_APP_PATH or install GaiaFusion)"
  fi

  python3 "${ROOT}/scripts/mcp_mac_cell_probe.py" >"$MAC_TMP"
  FAIL_VAL="$(python3 -c "import json; print(json.load(open('$MAC_TMP')).get('fail') or '')")"
  if [[ -n "$FAIL_VAL" ]]; then
    die "phase4 mac cell probe fail: ${FAIL_VAL}"
  fi
  phase4_status="CURE"
else
  phase4_status="SKIPPED_NON_DARWIN"
  echo 'null' >"$MAC_TMP"
fi

loop_receipt_rel=""
loop_terminal="SKIPPED"
if [[ "$SKIP_LOOP" != "1" ]]; then
  echo "## phase 5 fusion_ui_self_heal_loop (MCP conversation + healing ladder)"
  python3 "${ROOT}/scripts/fusion_ui_self_heal_loop.py" || die "phase5 fusion_ui_self_heal_loop"
  LOOP_RECEIPT_ABS="$(ls -t "${ROOT}/evidence/fusion_control"/fusion_ui_self_heal_loop_receipt_*.json 2>/dev/null | head -1)"
  if [[ -z "${LOOP_RECEIPT_ABS:-}" ]]; then
    die "phase5 fusion_ui_self_heal_loop receipt missing"
  fi
  loop_receipt_rel="${LOOP_RECEIPT_ABS#${ROOT}/}"
  loop_terminal="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1],encoding='utf-8')).get('terminal',''))" "$LOOP_RECEIPT_ABS" 2>/dev/null || echo "UNKNOWN")"
else
  loop_terminal="SKIPPED_OPERATOR_ENV"
fi

if [[ "$SKIP_APP" == "1" ]]; then
  echo "## phase 6 verify_gaiafusion_working_app — SKIPPED (OPERATOR_CLOSURE_SKIP_WORKING_APP=1)"
  python3 - "$RECEIPT" "$TS_ISO" "${LOG#${ROOT}/}" "$MAC_TMP" "$phase4_status" <<'PY'
import json, sys
from pathlib import Path
path, ts, log_rel, mac_path, p4s = sys.argv[1:6]
try:
    mac = json.load(open(mac_path, encoding="utf-8"))
except Exception:
    mac = None
doc = {
    "schema": "gaiaftcl_operator_fusion_mesh_closure_v1",
    "ts_utc": ts,
    "terminal": "CALORIE",
    "closure_kind": "fusion_mesh_preflight",
    "phases": {
        "plant_adapters": True,
        "fusion_sidecar_bundle": True,
        "mesh_green_probe": True,
        "mac_cell_probe": p4s,
        "self_heal_loop": "see_loop_receipt",
        "gaiafusion_working_app": "SKIPPED_OPERATOR_ENV",
    },
    "mac_cell_detail": mac,
    "log": log_rel,
}
Path(path).write_text(json.dumps(doc, indent=2), encoding="utf-8")
PY
  if [[ -n "$loop_receipt_rel" ]]; then
    python3 - "$RECEIPT" "$loop_receipt_rel" "$loop_terminal" <<'PY'
import json,sys
path, receipt_rel, term = sys.argv[1:4]
doc = json.load(open(path, encoding="utf-8"))
doc["self_heal_loop_receipt"] = receipt_rel
doc["self_heal_loop_terminal"] = term
json.dump(doc, open(path, "w", encoding="utf-8"), indent=2)
print()
PY
  fi
  echo "STATE: CALORIE (preflight — working-app verify skipped)"
  echo "RECEIPT: $RECEIPT"
  echo "LOG: $LOG"
  exit 0
fi

echo "## phase 6 verify_gaiafusion_working_app (full operator gate)"
bash "${ROOT}/scripts/verify_gaiafusion_working_app.sh" || die "phase6 verify_gaiafusion_working_app"

VERIFY_REL="${ROOT}/evidence/fusion_control/gaiafusion_working_app_verify_receipt.json"
VERIFY_WR="${VERIFY_REL#${ROOT}/}"
python3 - "$RECEIPT" "$TS_ISO" "${LOG#${ROOT}/}" "$MAC_TMP" "$phase4_status" "$VERIFY_REL" "$VERIFY_WR" <<'PY'
import json, sys
from pathlib import Path
path, ts, log_rel, mac_path, p4s, verify_path, verify_wr = sys.argv[1:8]
try:
    mac = json.load(open(mac_path, encoding="utf-8"))
except Exception:
    mac = None
wts = ""
try:
    w = json.load(open(verify_path, encoding="utf-8"))
    wts = w.get("ts_utc") or ""
except OSError:
    pass
doc = {
    "schema": "gaiaftcl_operator_fusion_mesh_closure_v1",
    "ts_utc": ts,
    "terminal": "CALORIE",
    "closure_kind": "fusion_mesh_full",
    "phases": {
        "plant_adapters": True,
        "fusion_sidecar_bundle": True,
        "mesh_green_probe": True,
        "mac_cell_probe": p4s,
        "self_heal_loop": "see_loop_receipt",
        "gaiafusion_working_app": True,
    },
    "mac_cell_detail": mac,
    "self_heal_loop_receipt": None,
    "self_heal_loop_terminal": None,
    "working_app_verify_receipt": verify_wr,
    "working_app_ts_utc": wts or None,
    "log": log_rel,
}
Path(path).write_text(json.dumps(doc, indent=2), encoding="utf-8")
PY
if [[ -n "$loop_receipt_rel" ]]; then
  python3 - "$RECEIPT" "$loop_receipt_rel" "$loop_terminal" <<'PY'
import json,sys
path, receipt_rel, term = sys.argv[1:4]
doc = json.load(open(path, encoding="utf-8"))
doc["self_heal_loop_receipt"] = receipt_rel
doc["self_heal_loop_terminal"] = term
json.dump(doc, open(path, "w", encoding="utf-8"), indent=2)
print()
PY
fi

echo "STATE: CALORIE"
echo "RECEIPT: $RECEIPT"
echo "LOG: $LOG"
exit 0
