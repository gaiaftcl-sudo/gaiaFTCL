#!/usr/bin/env bash
# Mac cell — full closure DAG without IDE/agent: fleet witness → optional substrate ingest → GaiaFusion release smoke.
# Writes one merged receipt: evidence/fusion_control/mac_cell_autonomous_closure_receipt.json
#
# Env:
#   MAC_CELL_REQUIRE_SUBSTRATE_INGEST (default 0) — if 1, exit non-zero when ingest is not CALORIE (2xx).
#   MAC_CELL_SKIP_FLEET_WITNESS (default 0) — if 1, skip witness_mac_cell_fleet_health.sh
#   MAC_CELL_SKIP_RELEASE_SMOKE (default 0) — if 1, skip run_gaiafusion_release_smoke.sh (for partial runs)
#   Release smoke inherits env (see `run_gaiafusion_release_smoke.sh`): e.g. GAIAFUSION_SKIP_XCTEST,
#   GAIAFUSION_SKIP_WORKING_APP_VERIFY, GAIAFUSION_SKIP_USD_PROBE_CLI, GAIAFUSION_USD_PROBE_SIGKILL_OK.
#   FUSION_UI_PORT — passed to fleet witness
#   GAIAFTCL_GATEWAY_URL / GAIAFTCL_INTERNAL_KEY — for ingest (see witness_mac_vqbit_substrate_ingest.sh)
#
# Host Mac (arm64, non-CI): GAIAFUSION_SKIP_* cleared — scripts/lib/gaiafusion_host_c4_lock.sh
# Override: GAIAFUSION_ALLOW_SKIP_ON_HOST=1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/gaiafusion_host_c4_lock.sh"
gaiafusion_host_strip_skip_leak

EV="$ROOT/evidence/fusion_control"
mkdir -p "$EV"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUT="$EV/mac_cell_autonomous_closure_receipt.json"

FLEET_JSON="$EV/mac_cell_fleet_health_witness.json"
INGEST_JSON="$EV/mac_vqbit_substrate_ingest_receipt.json"
SMOKE_JSON="$EV/gaiafusion_release_smoke_receipt.json"

REQ_INGEST="${MAC_CELL_REQUIRE_SUBSTRATE_INGEST:-0}"

fleet_rc=0
ingest_rc=0
smoke_rc=0

if [[ "$(uname -s)" != "Darwin" ]]; then
  jq -n \
    --arg ts "$TS" \
    --arg host "$(uname -s)" \
    '{
      schema: "gaiaftcl_mac_cell_autonomous_closure_v1",
      ts_utc: $ts,
      terminal: "REFUSED",
      reason: "requires_darwin",
      uname: $host,
      operator_required: ["Run this script on macOS with Swift toolchain for release smoke."]
    }' >"$OUT"
  echo "REFUSED: run_mac_cell_autonomous_closure.sh requires Darwin — wrote $OUT" >&2
  exit 3
fi

if [[ "${MAC_CELL_SKIP_FLEET_WITNESS:-0}" != "1" ]]; then
  bash "$ROOT/scripts/witness_mac_cell_fleet_health.sh" "$FLEET_JSON" || fleet_rc=$?
else
  fleet_rc=99
fi

bash "$ROOT/scripts/witness_mac_vqbit_substrate_ingest.sh" "$INGEST_JSON" || ingest_rc=$?

if [[ "${MAC_CELL_SKIP_RELEASE_SMOKE:-0}" != "1" ]]; then
  bash "$ROOT/scripts/run_gaiafusion_release_smoke.sh" || smoke_rc=$?
else
  smoke_rc=99
fi

python3 - "$OUT" "$TS" "$FLEET_JSON" "$INGEST_JSON" "$SMOKE_JSON" "$fleet_rc" "$ingest_rc" "$smoke_rc" "$REQ_INGEST" "$ROOT" <<'PY'
import json, sys
from pathlib import Path

out_path = sys.argv[1]
ts = sys.argv[2]
fleet_p, ingest_p, smoke_p = sys.argv[3], sys.argv[4], sys.argv[5]
fleet_rc, ingest_rc, smoke_rc = int(sys.argv[6]), int(sys.argv[7]), int(sys.argv[8])
req_ingest = sys.argv[9] == "1"
root = sys.argv[10]

def load(p):
    path = Path(p)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"_error": "invalid_json", "path": str(path)}

fleet = load(fleet_p)
ingest = load(ingest_p)
smoke = load(smoke_p)

blockers = []
if fleet_rc not in (0, 99):
    blockers.append(f"fleet_witness_failed_rc_{fleet_rc}")
if ingest_rc == 2:
    blockers.append("substrate_ingest: set GAIAFTCL_GATEWAY_URL and GAIAFTCL_INTERNAL_KEY for universal_ingest seal")
elif ingest_rc == 1:
    blockers.append("substrate_ingest: HTTP or network failure (see mac_vqbit_substrate_ingest_receipt.json)")
if smoke_rc not in (0, 99):
    blockers.append("release_smoke_failed: fix GaiaFusion build/tests or fusion_mac_app_gate (see gaiafusion_release_smoke_receipt.json)")

# Ingest optional unless required
if req_ingest and ingest_rc != 0:
    blockers.append("MAC_CELL_REQUIRE_SUBSTRATE_INGEST=1 but ingest did not succeed")

fleet_partial = False
if fleet and isinstance(fleet.get("fleet"), list):
    for row in fleet["fleet"]:
        c = row.get("http_code", 0)
        if c < 200 or c >= 300:
            fleet_partial = True
            break
if fleet and fleet.get("mac_leaf", {}).get("http_code", 0) not in (200,):
    fleet_partial = True

# Terminal for whole run
if smoke_rc != 0 and smoke_rc != 99:
    term = "REFUSED"
elif smoke_rc == 99:
    term = "PARTIAL"
elif req_ingest and ingest_rc != 0:
    term = "REFUSED"
elif ingest_rc == 1 or fleet_rc not in (0, 99):
    term = "PARTIAL"
elif fleet_partial or ingest_rc == 2:
    term = "PARTIAL"
else:
    term = "CURE"

# "Without operator next time" — machine did everything available in-repo; only sovereign creds / WAN block full autonomy
operator_required = []
if ingest_rc == 2:
    operator_required.append("Provide GAIAFTCL_GATEWAY_URL + GAIAFTCL_INTERNAL_KEY on this Mac for substrate ingest, or accept PARTIAL local-only vQbit.")
if fleet_partial:
    operator_required.append("Fleet HTTP codes not all 2xx from this network path — fix routing/firewall or accept PARTIAL mesh witness.")
if smoke_rc not in (0, 99):
    operator_required.append("Repair GaiaFusion / gate failures until release smoke is CURE.")
if smoke_rc == 99:
    operator_required.append("Release smoke was skipped (MAC_CELL_SKIP_RELEASE_SMOKE=1); re-run without skip for full executable spine.")

without_help_next_run = len(operator_required) == 0 and term == "CURE"

doc = {
    "schema": "gaiaftcl_mac_cell_autonomous_closure_v1",
    "ts_utc": ts,
    "terminal": term,
    "phases": {
        "fleet_witness": {
            "script": "scripts/witness_mac_cell_fleet_health.sh",
            "receipt": fleet_p[len(root) + 1 :] if fleet_p.startswith(root) else fleet_p,
            "rc": fleet_rc,
            "skipped": fleet_rc == 99,
        },
        "substrate_ingest": {
            "script": "scripts/witness_mac_vqbit_substrate_ingest.sh",
            "receipt": ingest_p[len(root) + 1 :] if ingest_p.startswith(root) else ingest_p,
            "rc": ingest_rc,
            "terminal": (ingest or {}).get("terminal"),
        },
        "release_smoke": {
            "script": "scripts/run_gaiafusion_release_smoke.sh",
            "receipt": smoke_p[len(root) + 1 :] if smoke_p.startswith(root) else smoke_p,
            "rc": smoke_rc,
            "skipped": smoke_rc == 99,
            "swift_xctest_executed": (smoke or {}).get("swift_xctest_executed"),
        },
    },
    "autonomy": {
        "without_operator_for_executable_spine": without_help_next_run,
        "operator_required": operator_required,
        "meaning": "Executable spine = fleet witness + ingest (if creds) + Swift smoke. Empty operator_required and terminal CURE means the limb adds no manual steps beyond sovereign secrets already on disk.",
    },
    "blockers": blockers,
}

Path(out_path).write_text(json.dumps(doc, indent=2), encoding="utf-8")
PY

# Exit code policy: smoke is the hard gate; optional ingest failure does not fail unless required
if [[ "${MAC_CELL_SKIP_RELEASE_SMOKE:-0}" != "1" ]] && [[ "$smoke_rc" -ne 0 ]]; then
  echo "REFUSED: release smoke rc=$smoke_rc — $OUT" >&2
  exit "$smoke_rc"
fi
if [[ "$REQ_INGEST" == "1" ]] && [[ "$ingest_rc" -ne 0 ]]; then
  echo "REFUSED: MAC_CELL_REQUIRE_SUBSTRATE_INGEST=1 but ingest rc=$ingest_rc — $OUT" >&2
  exit "$ingest_rc"
fi

echo "CALORIE: mac cell autonomous closure — $OUT"
exit 0
