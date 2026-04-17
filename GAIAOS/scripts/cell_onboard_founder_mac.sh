#!/usr/bin/env bash
# Founder Mac: source ~/.gaiaftcl/onboard_wallet.env then run cell_onboard + gaia_mount with GAIAFTCL_ONBOARD_WALLET.
# Users: same file with their own 0x address, or pass --wallet 0x… on the command line.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${GAIAFTCL_ONBOARD_ENV_FILE:-${HOME}/.gaiaftcl/onboard_wallet.env}"
BIN="$ROOT/deploy/mac_cell_mount/bin"

die() { echo "REFUSED: cell_onboard_founder_mac: $*" >&2; exit 1; }

WALLET_CLI=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wallet) WALLET_CLI="${2:-}"; shift 2 ;;
    *) die "unknown arg: $1 (use --wallet 0x...)" ;;
  esac
done

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  set +u
  source "$ENV_FILE"
  set -u
fi

WALLET="${WALLET_CLI:-${GAIAFTCL_ONBOARD_WALLET:-}}"
[[ -n "$WALLET" ]] || die "set GAIAFTCL_ONBOARD_WALLET in $ENV_FILE or pass --wallet 0x…"

if ! [[ "$WALLET" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
  die "wallet must be 0x + 40 hex chars"
fi

bash "$BIN/cell_onboard.sh" --wallet "$WALLET"
bash "$BIN/gaia_mount" --wallet "$WALLET"

echo "CALORIE: Founder Mac onboard + mount complete for wallet=${WALLET:0:10}…"
echo "NEXT: NATS heartbeat (bin/fusion_mesh_mooring_heartbeat.sh) and fusion_cell_status_nats_publish.sh when mesh is up"
echo "NEXT: bash scripts/fusion_moor_preflight.sh && bash scripts/fusion_phase0_gate.sh"
