#!/usr/bin/env zsh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "${ROOT}"
RG_BIN="$(command -v rg || true)"

fail() {
  print "REFUSED:$1:$2" >&2
  exit "${3:-1}"
}

require_file_size() {
  local path="$1"
  local min_bytes="$2"
  local code="$3"
  [[ -f "${path}" ]] || fail "${code}" "missing required asset: ${path}" 1
  local bytes
  bytes=$(/usr/bin/wc -c < "${path}" | /usr/bin/tr -d ' ')
  (( bytes >= min_bytes )) || fail "${code}" "asset too small (${bytes} < ${min_bytes}): ${path}" 1
}

require_no_remote_links() {
  local path="$1"
  local code="$2"
  [[ -n "${RG_BIN}" ]] || fail "${code}" "rg not available for link policy check" 1
  if "${RG_BIN}" -n "https?://|s3://|gs://" "${path}" >/dev/null 2>&1; then
    fail "${code}" "remote URL reference found in ${path}; resources must be in-repo" 1
  fi
}

require_not_contains() {
  local path="$1"
  local regex="$2"
  local code="$3"
  [[ -n "${RG_BIN}" ]] || fail "${code}" "rg not available for semantic collision check" 1
  if "${RG_BIN}" -n "${regex}" "${path}" >/dev/null 2>&1; then
    fail "${code}" "forbidden semantic token found in ${path}" 1
  fi
}

# Real asset gates: these thresholds prevent proxy/stub files from passing.
require_file_size "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.fblob" 1000000 "GW_REFUSE_FRANKLIN_PASSY_FLOB_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.usdz" 5000000 "GW_REFUSE_FRANKLIN_PASSY_USDZ_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.ztl" 1000000 "GW_REFUSE_FRANKLIN_PASSY_ZTL_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/materials/Franklin_Z3_Materials.metallib" 50000 "GW_REFUSE_FRANKLIN_Z3_METALLIB_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/spectral_luts/beaver_cap_spectral_lut.exr" 10000 "GW_REFUSE_FRANKLIN_BEAVER_LUT_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/spectral_luts/anisotropic_flow_map.exr" 10000 "GW_REFUSE_FRANKLIN_ANISO_FLOW_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/spectral_luts/claret_silk_degradation.exr" 10000 "GW_REFUSE_FRANKLIN_CLARET_LUT_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc/Manifest.json" 100 "GW_REFUSE_FRANKLIN_STYLETTS_MODEL_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/voice/ipa_viseme_map.json" 100 "GW_REFUSE_FRANKLIN_IPA_MAP_MISSING"
require_file_size "cells/franklin/AVATAR_MANIFEST.yaml" 100 "GW_REFUSE_FRANKLIN_AVATAR_MANIFEST_MISSING"
require_file_size "cells/franklin/Franklin_Cell.entitlements" 100 "GW_REFUSE_FRANKLIN_ENTITLEMENTS_MISSING"
require_file_size "cells/franklin/avatar/bundle_assets/RESOURCE_LOCK.yaml" 50 "GW_REFUSE_FRANKLIN_RESOURCE_LOCK_MISSING"

require_no_remote_links "cells/franklin/AVATAR_MANIFEST.yaml" "GW_REFUSE_FRANKLIN_REMOTE_RESOURCE_LINK"
require_no_remote_links "cells/franklin/avatar/bundle_assets/manifests/Franklin_Data.json" "GW_REFUSE_FRANKLIN_REMOTE_RESOURCE_LINK"
require_no_remote_links "cells/franklin/avatar/bundle_assets/RESOURCE_LOCK.yaml" "GW_REFUSE_FRANKLIN_REMOTE_RESOURCE_LINK"
require_file_size "cells/franklin/avatar/bundle_assets/provenance/vendored_assets.json" 50 "GW_REFUSE_FRANKLIN_PROVENANCE_MISSING"
require_not_contains "cells/franklin/avatar/bundle_assets/provenance/vendored_assets.json" "(?i)submarine|torpedo|warship|nasa.*ben-franklin|ben%20franklin\\.glb" "GW_REFUSE_FRANKLIN_SEMANTIC_COLLISION_PROVENANCE"

if [[ -n "${RG_BIN}" ]] && "${RG_BIN}" -n "HeadProxy" "cells/franklin/avatar/bundle_assets/meshes/franklin_passy_v1.usda" >/dev/null 2>&1; then
  fail "GW_REFUSE_FRANKLIN_PROXY_MESH_PRESENT" "proxy mesh still present in franklin_passy_v1.usda" 1
fi

print "CALORIE:FRANKLIN-PASSY-ASSETS:all required files present and above minimum size"
