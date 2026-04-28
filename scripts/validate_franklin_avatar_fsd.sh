#!/usr/bin/env zsh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "${ROOT}"

fail() {
  print "REFUSED:$1:$2" >&2
  exit "${3:-1}"
}

json_count() {
  local dir="$1"
  [[ -d "${dir}" ]] || { print 0; return; }
  local c
  c=$(/bin/ls "${dir}"/*.json 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
  print "${c:-0}"
}

mesh_exists() {
  local base="cells/franklin/avatar/bundle_assets/meshes/franklin_passy_v1"
  local ext
  for ext in usdz usda usdc obj gltf glb; do
    [[ -f "${base}.${ext}" ]] && return 0
  done
  return 1
}

must_exist() {
  local path="$1"
  local code="$2"
  local msg="$3"
  [[ -f "${path}" ]] || fail "${code}" "${msg}: ${path}" 215
}

must_dir() {
  local path="$1"
  local code="$2"
  local msg="$3"
  [[ -d "${path}" ]] || fail "${code}" "${msg}: ${path}" 215
}

if [[ -f "scripts/require_franklin_passy_assets.sh" ]]; then
  zsh "scripts/require_franklin_passy_assets.sh" "${ROOT}" >/dev/null 2>&1 || \
    fail "GW_REFUSE_FRANKLIN_FSD_PASSY_ASSETS_MISSING" "Required Passy assets are missing or undersized" 216
else
  fail "GW_REFUSE_FRANKLIN_FSD_PASSY_GATE_SCRIPT_MISSING" "Missing scripts/require_franklin_passy_assets.sh" 217
fi

[[ -f "GAIAOS/macos/Franklin/Package.swift" ]] || fail "GW_REFUSE_FRANKLIN_FSD_APP_MISSING" "Franklin package missing" 201
[[ -f "GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinAvatarRuntime.swift" ]] || fail "GW_REFUSE_FRANKLIN_FSD_RUNTIME_MISSING" "Avatar runtime missing" 202
[[ -f "GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinLiveIOServices.swift" ]] || fail "GW_REFUSE_FRANKLIN_FSD_LIVEIO_MISSING" "Live IO service missing" 203
[[ -f "GAIAOS/macos/Franklin/Sources/FranklinApp/OperatorSurfaceModel.swift" ]] || fail "GW_REFUSE_FRANKLIN_FSD_OPERATOR_MODEL_MISSING" "Operator model missing" 204
[[ -f "scripts/compile_franklin_reality_assets.sh" ]] || fail "GW_REFUSE_FRANKLIN_FSD_REALITY_PIPELINE_MISSING" "Reality pipeline script missing" 218

[[ -f "cells/franklin/avatar/Cargo.toml" ]] || fail "GW_REFUSE_FRANKLIN_FSD_RUST_WS_MISSING" "Avatar Rust workspace missing" 205
[[ -f "cells/franklin/avatar/scripts/build_bundle.zsh" ]] || fail "GW_REFUSE_FRANKLIN_FSD_BUNDLE_SCRIPT_MISSING" "Bundle signing script missing" 213
[[ -f "substrate/HASH_LOCKS.yaml" ]] || fail "GW_REFUSE_FRANKLIN_FSD_HASH_LOCKS_MISSING" "Hash locks missing" 214
for crate in avatar-core avatar-tts avatar-render avatar-bridge avatar-runtime; do
  [[ -f "cells/franklin/avatar/crates/${crate}/Cargo.toml" ]] || fail "GW_REFUSE_FRANKLIN_FSD_RUST_CRATE_MISSING" "Missing crate ${crate}" 206
done

(( $(json_count "cells/franklin/avatar/bundle_assets/illuminants") >= 4 )) || fail "GW_REFUSE_FRANKLIN_FSD_ILLUMINANTS" "Illuminants contract not met" 207
(( $(json_count "cells/franklin/avatar/bundle_assets/pose_templates/viseme") >= 11 )) || fail "GW_REFUSE_FRANKLIN_FSD_VISEMES" "Viseme contract not met" 208
(( $(json_count "cells/franklin/avatar/bundle_assets/pose_templates/expression") >= 12 )) || fail "GW_REFUSE_FRANKLIN_FSD_EXPRESSIONS" "Expression contract not met" 209
(( $(json_count "cells/franklin/avatar/bundle_assets/pose_templates/posture") >= 6 )) || fail "GW_REFUSE_FRANKLIN_FSD_POSTURES" "Posture contract not met" 210
mesh_exists || fail "GW_REFUSE_FRANKLIN_FSD_MESH" "Mesh contract not met" 211
[[ -f "cells/franklin/avatar/bundle_assets/voice/franklin_voice_profile.json" ]] || fail "GW_REFUSE_FRANKLIN_FSD_VOICE_PROFILE" "Voice profile missing" 212
must_exist "cells/franklin/avatar/bundle_assets/manifests/Franklin_Data.json" "GW_REFUSE_FRANKLIN_FSD_DATA_MANIFEST_MISSING" "Franklin data manifest missing"
must_exist "cells/franklin/avatar/bundle_assets/schemas/Franklin_M8.usda" "GW_REFUSE_FRANKLIN_FSD_M8_SCHEMA_MISSING" "Franklin M8 schema missing"
must_exist "cells/franklin/avatar/bundle_assets/schemas/FranklinSubstrate.usda" "GW_REFUSE_FRANKLIN_FSD_SUBSTRATE_SCHEMA_MISSING" "Franklin substrate schema missing"
must_exist "GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinSprout.swift" "GW_REFUSE_FRANKLIN_FSD_RUNTIME_BRIDGE_MISSING" "Franklin runtime bridge missing"
must_exist "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.usdz" "GW_REFUSE_FRANKLIN_FSD_USDZ_MISSING" "Franklin USDZ missing"
must_exist "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.ztl" "GW_REFUSE_FRANKLIN_FSD_ZTL_MISSING" "Franklin ZTL source missing"
must_dir "cells/franklin/avatar/bundle_assets/Franklin.rkassets" "GW_REFUSE_FRANKLIN_FSD_RKASSETS_MISSING" "Franklin rkassets bundle missing"

if [[ -d "cells/franklin/avatar/bundle_assets/pose_templates" ]]; then
  must_exist "cells/franklin/avatar/bundle_assets/pose_templates/gout_favor_left.json" "GW_REFUSE_FRANKLIN_FSD_POSTURE_GOUT_MISSING" "Required posture template missing"
  must_exist "cells/franklin/avatar/bundle_assets/pose_templates/sedan_chair_transit.json" "GW_REFUSE_FRANKLIN_FSD_POSTURE_SEDAN_MISSING" "Required posture template missing"
  must_exist "cells/franklin/avatar/bundle_assets/pose_templates/bifocal_reading_dip.json" "GW_REFUSE_FRANKLIN_FSD_POSTURE_BIFOCAL_MISSING" "Required posture template missing"
fi

print "CALORIE:FRANKLIN-AVATAR-FSD:all contracts satisfied"
