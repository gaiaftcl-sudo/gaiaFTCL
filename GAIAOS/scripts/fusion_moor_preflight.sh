#!/usr/bin/env bash
# DMG / Mac leaf moor gate: identity + mount receipt + fresh mesh heartbeat state (same semantics as fusionS4MeshMoor).
# Exit 0 = CALORIE, non-zero = REFUSED. Override moor state path: FUSION_MOORING_STATE_JSON; projection: FUSION_PROJECTION_JSON.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"

die() { echo "REFUSED: fusion_moor_preflight: $*" >&2; exit 1; }

GAIA_DIR="${HOME}/.gaiaftcl"
IDENT="${GAIA_DIR}/cell_identity.json"
MOUNT="${GAIA_DIR}/mount_receipt.json"
MOOR_STATE="${FUSION_MOORING_STATE_JSON:-$GAIA_DIR/fusion_mesh_mooring_state.json}"
PROJ="${FUSION_PROJECTION_JSON:-$GAIA_ROOT/deploy/fusion_mesh/fusion_projection.json}"

[[ -f "$IDENT" ]] || die "missing $IDENT (run cell_onboard)"
[[ -f "$MOUNT" ]] || die "missing $MOUNT (gaia_mount / mount receipt)"
[[ -f "$MOOR_STATE" ]] || die "missing $MOOR_STATE (run fusion_mesh_mooring_heartbeat after wire heartbeat)"
[[ -f "$PROJ" ]] || die "missing projection $PROJ"

command -v jq >/dev/null 2>&1 || die "jq required"
command -v python3 >/dev/null 2>&1 || die "python3 required (UTC age parse)"

max_sec="$(jq -r '.payment_projection.mesh_heartbeat_max_sec // 86400' "$PROJ")"
[[ "$max_sec" =~ ^[0-9]+$ ]] || max_sec=86400

last="$(jq -r '.last_mesh_ok_utc // empty' "$MOOR_STATE")"
[[ -n "$last" ]] || die "$MOOR_STATE has no last_mesh_ok_utc"

age_sec="$(python3 -c "
import datetime, sys
s = sys.argv[1]
d = datetime.datetime.fromisoformat(s.replace('Z', '+00:00'))
now = datetime.datetime.now(datetime.timezone.utc)
print(int((now - d.astimezone(datetime.timezone.utc)).total_seconds()))
" "$last")"

if [[ "$age_sec" -gt "$max_sec" ]]; then
  die "mesh heartbeat stale: last_mesh_ok_utc=$last age_sec=$age_sec max_sec=$max_sec (see mesh_heartbeat_max_sec in fusion_projection.json)"
fi

echo "CALORIE: fusion_moor_preflight OK (identity + mount + fresh mesh state, age_sec=$age_sec max_sec=$max_sec)"
exit 0
