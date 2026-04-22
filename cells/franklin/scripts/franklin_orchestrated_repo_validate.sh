#!/usr/bin/env zsh
# Franklin-led repo validation: Mac admin cell (Franklin) + Health cell (IQ/OQ/PQ GAMP5 pack) + optional fusion registry.
# This is the **single** recommended entry to avoid drift between "apps" and the qualified shell path.
#
# Usage (from FoT8D / gaiaFTCL repo root):
#   zsh cells/franklin/scripts/franklin_orchestrated_repo_validate.sh
#
# Environment:
#   FRANKLIN_ONLY=1              — run only `franklin_mac_full_package_validate.sh` (no Health cell)
#   SKIP_FUSION_GAME_REGISTRY=0 — default: run `validate_discord_game_rooms.sh` (registry Python only; no npm servers)
#   INTEGRATION_*                 — see `cells/fusion/scripts/validate_discord_game_rooms.sh` for full Discord/Playwright games
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRANKLIN="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$(cd "$FRANKLIN/../.." && pwd)"
HEALTH_V="$REPO/cells/health/scripts/health_cell_gamp5_validate.sh"
FUSION_GR="$REPO/cells/fusion/scripts/validate_discord_game_rooms.sh"

cd "$REPO"

echo "== Franklin orchestrated repo validate (root: $REPO)"
echo "== 1) Mac cell — full Franklin pack (Swift + doc lock + pins + receipts + fo_cell_substrate + MacFranklin.app)"
zsh "$FRANKLIN/scripts/franklin_mac_full_package_validate.sh"

if [[ "${FRANKLIN_ONLY:-0}" == "1" ]]; then
  echo "== Franklin orchestrated: OK (FRANKLIN_ONLY=1, skipped Health + Fusion checks)"
  exit 0
fi

echo "== 2) Health cell — GAMP5 (wiki, catalog, OWL-MITO, OWL-NUTRITION IQ/OQ/PQ, peptide, cargo test workspace)"
zsh "$HEALTH_V"

if [[ "${SKIP_FUSION_GAME_REGISTRY:-0}" == "1" ]]; then
  echo "== 3) Fusion — skipped (SKIP_FUSION_GAME_REGISTRY=1)"
elif [[ ! -d "$REPO/cells/fusion/services/discord_frontier" ]]; then
  echo "== 3) Fusion / Discord game rooms — skip (no cells/fusion/services/discord_frontier in this tree)"
else
  if [[ -f "$FUSION_GR" ]]; then
    echo "== 3) Fusion / Discord game rooms (registry + optional mesh/NATS; see script for INTEGRATION flags)"
    zsh "$FUSION_GR"
  else
    echo "== 3) Fusion — skip (not found: $FUSION_GR)" >&2
  fi
fi

echo "== Franklin orchestrated repo validate: OK"
exit 0
