#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AVATAR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MESH_DIR="${AVATAR_DIR}/bundle_assets/meshes"
SOURCE_DIR="${MESH_DIR}/sources"
SOURCE_GLB="${MESH_DIR}/Franklin_Passy_V2.glb"
SOURCE_USDA="${SOURCE_DIR}/Franklin_Passy_V2.usda"
SOURCE_USDZ="${SOURCE_DIR}/Franklin_Passy_V2.usdz"
RUNTIME_USDZ="${MESH_DIR}/Franklin_Passy_V2.usdz"

fail() {
  print "REFUSED:$1:$2" >&2
  exit 1
}

mkdir -p "${SOURCE_DIR}"
[[ -f "${SOURCE_GLB}" ]] || fail "GW_REFUSE_RUNTIME_USDZ_GLB_MISSING" "missing ${SOURCE_GLB}"

USDCAT_BIN="$(command -v usdcat || true)"
USDZIP_BIN="$(command -v usdzip || true)"
[[ -n "${USDCAT_BIN}" ]] || fail "GW_REFUSE_RUNTIME_USDZ_TOOL_MISSING" "usdcat not found"
[[ -n "${USDZIP_BIN}" ]] || fail "GW_REFUSE_RUNTIME_USDZ_TOOL_MISSING" "usdzip not found"

"${USDCAT_BIN}" "${SOURCE_GLB}" -o "${SOURCE_USDA}" >/dev/null 2>&1 || \
  fail "GW_REFUSE_RUNTIME_USDZ_CONVERT_FAILED" "usdcat failed converting GLB to USDA"
"${USDZIP_BIN}" -r "${SOURCE_USDZ}" "${SOURCE_USDA}" >/dev/null 2>&1 || \
  fail "GW_REFUSE_RUNTIME_USDZ_PACK_FAILED" "usdzip failed packing USDA to USDZ"
cp "${SOURCE_USDZ}" "${RUNTIME_USDZ}"

BYTES="$(/usr/bin/stat -f %z "${RUNTIME_USDZ}" 2>/dev/null || /usr/bin/stat -c %s "${RUNTIME_USDZ}")"
(( BYTES >= 5000000 )) || fail "GW_REFUSE_RUNTIME_USDZ_TOO_SMALL" "runtime usdz is ${BYTES} bytes (<5MB)"

print "CALORIE:FRANKLIN-RUNTIME-USDZ:${RUNTIME_USDZ} (${BYTES} bytes)"
