#!/usr/bin/env bash
# GaiaFTCL — "best control test" harness: fused Metal validation + retro DOS/Pascal IDE metrics frame.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/scripts/lib/turbo_frames.sh"
turbo_init_colors

export FUSION_VALIDATION_CYCLES="${FUSION_VALIDATION_CYCLES:-2000}"
export FUSION_DECLARED_KW="${FUSION_DECLARED_KW:-1.0}"
export FUSION_ENTROPY_TAX_EUR_PER_KW="${FUSION_ENTROPY_TAX_EUR_PER_KW:-0.10}"

APP="$ROOT/services/fusion_control_mac/dist/FusionControl.app/Contents/MacOS/fusion_control"
if [[ ! -x "$APP" ]]; then
  export FUSION_SKIP_POST_WITNESS=1
  bash "$ROOT/scripts/build_fusion_control_mac_app.sh" >/dev/null
fi

OUT="$(mktemp)"
set +e
"$APP" >"$OUT" 2>/tmp/fusion_control_err.$$
RC=$?
set -e
ERR="$(cat /tmp/fusion_control_err.$$ 2>/dev/null || true)"
rm -f /tmp/fusion_control_err.$$

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required"
  exit 1
fi

J() { jq -r "$1" "$OUT"; }

OK="$(J '.ok')"
CY_REQ="$(J '.cycles_requested')"
CY_OK="$(J '.cycles_completed')"
CY_FAIL="$(J '.cycles_failed')"
WORST="$(J '.worst_max_abs_error')"
WMS="$(J '.wall_time_ms')"
WUS="$(J '.wall_time_us')"
GPU="$(J '.gpu_wall_us')"
VER="$(J '.verify_wall_us')"
ENG="$(J '.validation_engine')"
KERN="$(J '.kernel')"
N="$(J '.n')"
TAX="$(J '.entropy_tax.tax_due_eur')"
RATE="$(J '.entropy_tax.rate_eur_per_kw')"
DKW="$(J '.entropy_tax.declared_kw')"
TSTAT="$(J '.entropy_tax.tax_status')"
TRE="$(J '.entropy_tax.treasury_env_configured')"
HOST="$(scutil --get ComputerName 2>/dev/null || hostname || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OSV="$(sw_vers -productVersion 2>/dev/null || echo n/a)"

turbo_clear

turbo_title_bar " GAIAFTCL CONTROL MATRIX — FUSION SECTOR "

turbo_top
turbo_row "  Turbo-style validation receipt  │  host: ${HOST:0:38}"
turbo_mid
turbo_row_val "Operating system    " "$OSV"
turbo_row_val "UTC timestamp       " "$TS"
turbo_row_val "Control binary      " "fusion_control (Metal)"
turbo_mid

if [[ "$OK" == "true" ]]; then
  RES="PASS"
else
  RES="FAIL"
fi
turbo_row_val "RESULT              " "$RES"
turbo_row_val "Sector              " "FUSION / Metal fused"
if [[ "$OK" == "true" ]]; then
  turbo_row "    ${GR}${B}*** PASS ***  all invariants within tolerance${RST}"
else
  turbo_row "    ${RD}${B}*** FAIL ***  see metrics above${RST}"
fi

turbo_row_val "Schema              " "$(J '.schema')"
turbo_row_val "Validation engine   " "$ENG"
turbo_row_val "Kernel              " "${KERN:0:39}"
turbo_row_val "Grid width n        " "$N"
turbo_row_val "Cycles req/ok/fail  " "$CY_REQ / $CY_OK / $CY_FAIL"
turbo_row_val "Worst |err| max     " "$WORST"
turbo_row_val "Wall (ms / µs)      " "$WMS / $WUS"
turbo_row_val "GPU wall (µs)       " "$GPU"
turbo_row_val "Verify wall (µs)    " "$VER"
turbo_mid
turbo_row_val "Entropy tax (EUR)   " "$TAX"
turbo_row_val "Rate EUR/kW         " "$RATE"
turbo_row_val "Declared kW         " "$DKW"
turbo_row_val "Tax status          " "$TSTAT"
turbo_row_val "Treasury env set    " "$TRE"
turbo_mid

if [[ "$OK" == "true" && "$CY_FAIL" == "0" ]]; then
  turbo_row "${GR}${B}>> ALL CONTROL LOOPS CLOSED — SUBSTRATE GREEN <<${RST}"
else
  turbo_row "${RD}${B}>> CONTROL INTERRUPT — INSPECT RECEIPT <<${RST}"
fi
[[ -n "$ERR" ]] && turbo_row "${RD}stderr:${RST} ${ERR:0:52}"

turbo_bot

printf '\n%s' "$DIM"
printf '  ── status line ────────────────────────────────────────────────\n'
printf '  exit_code=%s  receipt_bytes=%s   │   F1=Help n/a   ESC=Quit n/a   Alt-X=Exit n/a\n' "$RC" "$(wc -c <"$OUT" | tr -d ' ')"
printf '  load: FUSION_VALIDATION_CYCLES=%s FUSION_DECLARED_KW=%s\n' "${FUSION_VALIDATION_CYCLES}" "${FUSION_DECLARED_KW}"
printf '%s\n' "$RST"

LAST_RECEIPT="$ROOT/evidence/fusion_control/last_control_matrix_receipt.json"
mkdir -p "$(dirname "$LAST_RECEIPT")"
cp "$OUT" "$LAST_RECEIPT"

rm -f "$OUT"

if [[ "$RC" -ne 0 ]] || [[ "$OK" != "true" ]]; then
  exit 1
fi
