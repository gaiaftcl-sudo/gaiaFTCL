#!/usr/bin/env zsh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "${ROOT}"

fail() {
  print "REFUSED:$1:$2" >&2
  exit 1
}

run_with_timeout() {
  local seconds="$1"
  shift
  python3 - "$seconds" "$@" <<'PY'
import subprocess
import sys

timeout = int(sys.argv[1])
cmd = sys.argv[2:]
try:
    proc = subprocess.run(cmd, timeout=timeout, check=False)
    sys.exit(proc.returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)
PY
}

MESH_DIR="cells/franklin/avatar/bundle_assets/meshes"
SOURCE_USDZ="${MESH_DIR}/sources/Franklin_Passy_V2.usdz"
SOURCE_GLB="${MESH_DIR}/Franklin_Passy_V2.glb"
RKASSETS_DIR="cells/franklin/avatar/bundle_assets/Franklin.rkassets"
BUILD_DIR="cells/franklin/avatar/build/reality"

mkdir -p "${MESH_DIR}" "${RKASSETS_DIR}" "${BUILD_DIR}"

# Prefer the real production source USDZ when available. Only fall back to
# USDA packaging when no production source exists.
if [[ -f "${SOURCE_USDZ}" ]]; then
  cp "${SOURCE_USDZ}" "${MESH_DIR}/Franklin_Passy_V2.usdz"
elif [[ -f "${SOURCE_GLB}" ]]; then
  run_with_timeout 120 zsh "cells/franklin/avatar/scripts/produce_franklin_runtime_usdz.zsh" >/dev/null 2>&1 || \
    fail "GW_REFUSE_SELF_HEAL_USDZ_BUILD_FAILED" "unable to build Franklin_Passy_V2.usdz from glb source"
elif [[ ! -f "${MESH_DIR}/Franklin_Passy_V2.usdz" && -f "${MESH_DIR}/Franklin_Passy_V2.usda" ]]; then
  run_with_timeout 45 usdzip -r "${MESH_DIR}/Franklin_Passy_V2.usdz" "${MESH_DIR}/Franklin_Passy_V2.usda" >/dev/null 2>&1 || \
    fail "GW_REFUSE_SELF_HEAL_USDZ_PACK_FAILED" "unable to package Franklin_Passy_V2.usdz from usda"
fi

[[ -f "${MESH_DIR}/Franklin_Passy_V2.usdz" ]] || fail "GW_REFUSE_SELF_HEAL_USDZ_MISSING" "missing Franklin_Passy_V2.usdz"

# Refuse tiny non-production USDZ payloads.
USDZ_BYTES="$(/usr/bin/stat -f %z "${MESH_DIR}/Franklin_Passy_V2.usdz" 2>/dev/null || /usr/bin/stat -c %s "${MESH_DIR}/Franklin_Passy_V2.usdz")"
(( USDZ_BYTES >= 5000000 )) || fail "GW_REFUSE_SELF_HEAL_USDZ_TOO_SMALL" "Franklin_Passy_V2.usdz is ${USDZ_BYTES} bytes (<5MB production floor)"

# Keep rkassets in sync with latest usdz.
cp "${MESH_DIR}/Franklin_Passy_V2.usdz" "${RKASSETS_DIR}/Franklin_Passy_V2.usdz"

# Regenerate preview image that UI consumes as human fallback.
run_with_timeout 45 usdrecord "${MESH_DIR}/Franklin_Passy_V2.usdz" "${BUILD_DIR}/Franklin_preview.png" >/dev/null 2>&1 || \
  fail "GW_REFUSE_SELF_HEAL_PREVIEW_RENDER_FAILED" "unable to render Franklin_preview.png from usdz"

[[ -f "${BUILD_DIR}/Franklin_preview.png" ]] || fail "GW_REFUSE_SELF_HEAL_PREVIEW_MISSING" "Franklin_preview.png missing after render"

# Recompile runtime reality artifacts and enforce asset/FSD gates.
run_with_timeout 120 zsh "scripts/compile_franklin_reality_assets.sh" "${ROOT}" >/dev/null 2>&1 || \
  fail "GW_REFUSE_SELF_HEAL_REALITY_COMPILE_FAILED" "realitytool compile failed during preflight heal"
run_with_timeout 60 zsh "scripts/require_franklin_passy_assets.sh" "${ROOT}" >/dev/null 2>&1 || \
  fail "GW_REFUSE_SELF_HEAL_ASSET_GATE_FAILED" "asset gate failed after preflight heal"

# Validate baseline FSD contracts directly here to avoid recursive self-heal calls.
[[ -f "GAIAOS/macos/Franklin/Package.swift" ]] || fail "GW_REFUSE_SELF_HEAL_FSD_APP_MISSING" "Franklin package missing after heal"
[[ -f "cells/franklin/avatar/bundle_assets/manifests/Franklin_Data.json" ]] || fail "GW_REFUSE_SELF_HEAL_FSD_MANIFEST_MISSING" "Franklin_Data.json missing after heal"
[[ -f "cells/franklin/avatar/bundle_assets/schemas/Franklin_M8.usda" ]] || fail "GW_REFUSE_SELF_HEAL_FSD_M8_MISSING" "Franklin_M8.usda missing after heal"
[[ -f "cells/franklin/avatar/build/reality/Franklin_preview.png" ]] || fail "GW_REFUSE_SELF_HEAL_FSD_PREVIEW_MISSING" "Franklin_preview.png missing after heal"

print "CALORIE:FRANKLIN-FSD-SELF-HEAL:preflight complete"
