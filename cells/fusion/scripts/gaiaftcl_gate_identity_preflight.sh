#!/usr/bin/env bash
# Print once what fusion_phase0_gate.sh expects on the Founder Mac (~/.gaiaftcl/). Does not create secrets.
set -euo pipefail
G="${HOME}/.gaiaftcl"
echo "Phase 0 / moor gate expects (see scripts/fusion_phase0_gate.sh):"
echo "  $G/cell_identity.json"
echo "  $G/mount_receipt.json"
echo "  ${FUSION_MOORING_STATE_JSON:-$G/fusion_mesh_mooring_state.json}  (or run heartbeat)"
echo ""
missing=0
for f in "$G/cell_identity.json" "$G/mount_receipt.json"; do
  if [[ ! -f "$f" ]]; then
    echo "MISSING: $f"
    missing=1
  else
    echo "OK: $f"
  fi
done
if [[ "$missing" -ne 0 ]]; then
  echo ""
  echo "Sync sovereign receipts from your canonical source into ~/.gaiaftcl/ then run:"
  echo "  FUSION_PHASE0_SKIP_TRACK_F=0 FUSION_PHASE0_SKIP_NEGATIVE=0 bash scripts/fusion_phase0_gate.sh"
  exit 1
fi
exit 0
