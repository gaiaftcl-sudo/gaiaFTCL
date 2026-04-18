#!/usr/bin/env bash
# Contextual continuity — refuse "Broken Green": env + identity + phase0 REPORT + optional Docker snapshot witness.
# Exit 0 only when checks pass. Exit 1 = torsion (S4 projection ≠ C4).
# Env: GAIA_ROOT (default: repo root), FUSION_UI_PORT (default 8910), STRICT=1 (fail if REPORT exists but overall_ok false)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
REPORT="$GAIA_ROOT/evidence/fusion_control/phase0_gate/REPORT.json"
IDENT="${HOME}/.gaiaftcl/cell_identity.json"
MOUNT="${HOME}/.gaiaftcl/mount_receipt.json"
MOOR="${FUSION_MOORING_STATE_JSON:-${HOME}/.gaiaftcl/fusion_mesh_mooring_state.json}"
UI_PORT="${FUSION_UI_PORT:-8910}"
STRICT="${STRICT:-0}"
ERR=0

echo "[fusion_context_validate] GAIA_ROOT=$GAIA_ROOT FUSION_UI_PORT=$UI_PORT"

if [[ ! -d "$GAIA_ROOT/deploy/fusion_mesh" ]]; then
  echo "REFUSED: missing deploy/fusion_mesh under GAIA_ROOT"
  ERR=1
fi

if [[ ! -f "$IDENT" ]]; then
  echo "REFUSED: missing $IDENT — Phase 0 tracks B/D need sovereign cell identity on this host"
  ERR=1
else
  echo "OK: cell_identity.json present"
fi

if [[ ! -f "$MOUNT" ]]; then
  echo "WARN: missing $MOUNT (Track B moor receipt)"
  [[ "$STRICT" == "1" ]] && ERR=1
fi

if [[ ! -f "$MOOR" ]]; then
  echo "WARN: missing $MOOR (Track C moor state — run heartbeat)"
  [[ "$STRICT" == "1" ]] && ERR=1
fi

if [[ -f "$REPORT" ]]; then
  ok="$(jq -r '.overall_ok // false' "$REPORT" 2>/dev/null || echo false)"
  failed="$(jq '[.steps[] | select(.status == "failed")] | length' "$REPORT" 2>/dev/null || echo "?")"
  echo "[fusion_context_validate] REPORT.json overall_ok=$ok failed_steps=$failed"
  if [[ "$ok" != "true" ]] && [[ "$STRICT" == "1" ]]; then
    echo "REFUSED: REPORT exists but overall_ok is not true — re-run fusion_phase0_gate.sh without skip flags after fixing identity"
    ERR=1
  fi
else
  echo "WARN: no $REPORT yet — run scripts/fusion_phase0_gate.sh"
  [[ "$STRICT" == "1" ]] && ERR=1
fi

# Optional: live UI (Track F) when dev server expected
if command -v curl >/dev/null 2>&1; then
  code="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${UI_PORT}/api/fusion/fleet-digest" || true)"
  if [[ "$code" == "200" ]]; then
    echo "OK: fleet-digest HTTP 200 on :$UI_PORT"
  else
    echo "WARN: fleet-digest HTTP $code on :$UI_PORT (start npm run dev:fusion or align FUSION_UI_PORT)"
    [[ "$STRICT" == "1" ]] && ERR=1
  fi
fi

# Optional Docker: named volume has snapshot (best-effort; compose prefixes volume name)
if command -v docker >/dev/null 2>&1; then
  if docker volume ls -q 2>/dev/null | grep -q "fusion_fleet_evidence"; then
    echo "OK: docker volume matching *fusion_fleet_evidence* exists"
  else
    echo "INFO: no docker volume *fusion_fleet_evidence* (subscriber not deployed or different project name)"
  fi
fi

if [[ "$ERR" -ne 0 ]]; then
  echo "[fusion_context_validate] Terminal state: REFUSED (exit 1)"
  exit 1
fi
echo "[fusion_context_validate] Terminal state: CALORIE (exit 0)"
exit 0
