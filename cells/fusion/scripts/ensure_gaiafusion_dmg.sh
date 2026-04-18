#!/usr/bin/env bash
# Materialize dist/GaiaFusion.dmg for C4 mount invariant (invokes full facade build when missing).
# REFUSED if C4_INVARIANT_BUILD_DMG=0 and no DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${GAIAFUSION_DMG:-}"
if [[ -n "$DMG" && -f "$DMG" ]]; then
  echo "CALORIE: GAIAFUSION_DMG=$DMG"
  exit 0
fi

for f in "$ROOT/dist/GaiaFusion.dmg" "$ROOT/dist/"*GaiaFusion*.dmg; do
  if [[ -f "$f" ]]; then
    echo "CALORIE: GaiaFusion DMG present: $f"
    exit 0
  fi
done

if [[ "${C4_INVARIANT_BUILD_DMG:-1}" != "1" ]]; then
  echo "REFUSED: no GaiaFusion DMG under dist/ and C4_INVARIANT_BUILD_DMG=0"
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "REFUSED: GaiaFusion DMG build requires macOS (Darwin)"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "C4 ensure: building GaiaFTCL + GaiaFusion.dmg (long-running; Swift, FusionControl, optional Xcode)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exec bash "$ROOT/scripts/build_gaiaftcl_facade_dmg.sh"
