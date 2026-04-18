#!/usr/bin/env bash
# Session invariant (C4): keep executing the release spine until success or a hard REFUSED/BLOCKED.
# - Chains: closure battery → nine-cell witness → mesh snapshot → DOCX.
# - Does not "stop early" on narrative; failures are explicit non-zero exits with stderr witness.
#
# Env:
#   RELEASE_ALLOW_PARTIAL (default 0) — if 1, accept closure battery PARTIAL (non-uniform mesh)
#   RELEASE_SELF_HEAL_UNIFORM (default 0) — if 1 and NON_UNIFORM, run deploy_crystal_nine_cells.sh once then re-check uniformity
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
EV_REL="$ROOT/evidence/release"
EV_FUSION="$ROOT/evidence/fusion_control"
mkdir -p "$EV_REL"
mkdir -p "$EV_FUSION"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
RECEIPT_JSON="$EV_REL/SESSION_RELEASE_RECEIPT_${TS}.json"
LOG_TXT="$EV_REL/SESSION_RELEASE_LOG_${TS}.txt"
export ROOT RECEIPT_JSON LOG_TXT TS

ALLOW_PARTIAL="${RELEASE_ALLOW_PARTIAL:-0}"
SELF_HEAL_UNIFORM="${RELEASE_SELF_HEAL_UNIFORM:-0}"

exec > >(tee -a "$LOG_TXT") 2>&1

die_refused() {
  export REASON="$*"
  echo "REFUSED: $REASON" >&2
  REASON="$REASON" python3 <<'PY'
import json, os
from pathlib import Path
Path(os.environ["RECEIPT_JSON"]).write_text(json.dumps({
    "terminal": "REFUSED",
    "reason": os.environ.get("REASON", ""),
    "log": os.environ.get("LOG_TXT", ""),
}, indent=2), encoding="utf-8")
PY
  exit 1
}

latest_release_report_json() {
  python3 <<'PY'
import glob
import os
from pathlib import Path
root = Path(os.environ["ROOT"])
pat = root / "evidence" / "fusion_control" / "RELEASE_REPORT_*.json"
files = sorted(glob.glob(str(pat)), key=lambda p: Path(p).stat().st_mtime, reverse=True)
if not files:
    raise SystemExit(2)
print(files[0])
PY
}

read_report_state() {
  # One line: state<TAB>uniformity (bash 3.2–safe; no readarray)
  python3 -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); print(d.get('state','')+'\t'+d.get('uniformity',''))" "$1"
}

echo "=== run_full_release_session ts=$TS ==="

if [[ "${C4_CLEAR_RELEASE_DECK:-1}" == "1" ]] && [[ -f "$ROOT/scripts/clear_release_deck.sh" ]]; then
  echo "## 0 clear release deck (stale REPORT / SESSION archived)"
  bash "$ROOT/scripts/clear_release_deck.sh"
fi

echo "## 1 closure battery"
if ! bash "$ROOT/scripts/run_closure_battery.sh"; then
  die_refused "closure_battery exited non-zero"
fi

RP="$(latest_release_report_json)" || die_refused "no RELEASE_REPORT_*.json after closure battery"
IFS=$'\t' read -r STATE UNIFORM < <(read_report_state "$RP") || true
echo "closure_report: $RP state=$STATE uniformity=$UNIFORM"

if [[ "$UNIFORM" != "UNIFORM" ]]; then
  if [[ "$SELF_HEAL_UNIFORM" == "1" ]]; then
    echo "## 1b self-heal: deploy nine cells (RELEASE_SELF_HEAL_UNIFORM=1)"
    if ! bash "$ROOT/scripts/deploy_crystal_nine_cells.sh"; then
      die_refused "deploy_crystal_nine_cells failed"
    fi
    echo "## 1c re-run closure battery for uniformity"
    if ! bash "$ROOT/scripts/run_closure_battery.sh"; then
      die_refused "closure_battery after deploy failed"
    fi
    RP="$(latest_release_report_json)"
    IFS=$'\t' read -r STATE UNIFORM < <(read_report_state "$RP") || true
    echo "closure_report_after_deploy: $RP state=$STATE uniformity=$UNIFORM"
  fi
  if [[ "$UNIFORM" != "UNIFORM" ]]; then
    if [[ "$ALLOW_PARTIAL" == "1" ]]; then
      echo "WARN: NON_UNIFORM allowed (RELEASE_ALLOW_PARTIAL=1)"
    else
      die_refused "mesh non-uniform — set RELEASE_ALLOW_PARTIAL=1 to continue or RELEASE_SELF_HEAL_UNIFORM=1 to deploy+retry (report=$RP)"
    fi
  fi
fi

echo "## 3 nine-cell release witness"
if ! bash "$ROOT/scripts/verify_nine_cell_release.sh"; then
  die_refused "verify_nine_cell_release failed"
fi

echo "## 4 mesh health snapshot"
TSN="$(date -u +%Y%m%dT%H%M%SZ)"
MESH_TSV="$EV_REL/MESH_HEALTH_SNAPSHOT_${TSN}.tsv"
bash "$ROOT/scripts/mesh_health_snapshot.sh" >"$MESH_TSV"

echo "## 5 release DOCX"
DOCX_TS="$(date -u +%Y%m%dT%H%M%SZ)"
DOCX_OUT="$EV_FUSION/GAIAFTCL_PROD_RELEASE_${DOCX_TS}.docx"
if ! python3 "$ROOT/scripts/generate_release_docx.py" --repo-root "$ROOT" --json "$RP" --output "$DOCX_OUT"; then
  die_refused "generate_release_docx failed"
fi

export RP MESH_TSV DOCX_OUT

python3 <<'PY'
import json, os
from pathlib import Path
rec = {
    "terminal": "CALORIE",
    "ts_utc": os.environ["TS"],
    "closure_report_json": os.environ.get("RP", ""),
    "mesh_health_tsv": os.environ.get("MESH_TSV", ""),
    "docx": os.environ.get("DOCX_OUT", ""),
    "log": os.environ.get("LOG_TXT", ""),
}
Path(os.environ["RECEIPT_JSON"]).write_text(json.dumps(rec, indent=2), encoding="utf-8")
print(Path(os.environ["RECEIPT_JSON"]).read_text(encoding="utf-8"))
PY

echo "STATE: CALORIE"
echo "RECEIPT_JSON: $RECEIPT_JSON"
echo "LOG: $LOG_TXT"
