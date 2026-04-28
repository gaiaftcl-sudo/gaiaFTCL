#!/usr/bin/env zsh
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "${ROOT}"

usage() {
  cat <<'EOF'
Usage:
  scripts/vendor_franklin_assets.sh <repo-root> \
    --fblob /path/to/Franklin_Passy_V2.fblob \
    --metallib /path/to/Franklin_Z3_Materials.metallib \
    --beaver-lut /path/to/beaver_cap_spectral_lut.exr \
    --aniso-flow /path/to/anisotropic_flow_map.exr \
    --claret-lut /path/to/claret_silk_degradation.exr \
    --styletts-manifest /path/to/Manifest.json \
    [--source-registry "free3d-id1217,cgtrader-rigged,smithsonian-npg70-16"]

Notes:
  - This script stages already-downloaded assets into in-repo contract paths.
  - It does not fetch from the network.
EOF
}

fail() {
  print "REFUSED:$1:$2" >&2
  exit 1
}

[[ $# -lt 2 ]] && usage && exit 2

shift

typeset FBLOB=""
typeset METALLIB=""
typeset BEAVER=""
typeset ANISO=""
typeset CLARET=""
typeset MANIFEST=""
typeset SOURCES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fblob) FBLOB="$2"; shift 2 ;;
    --metallib) METALLIB="$2"; shift 2 ;;
    --beaver-lut) BEAVER="$2"; shift 2 ;;
    --aniso-flow) ANISO="$2"; shift 2 ;;
    --claret-lut) CLARET="$2"; shift 2 ;;
    --styletts-manifest) MANIFEST="$2"; shift 2 ;;
    --source-registry) SOURCES="$2"; shift 2 ;;
    *) fail "GW_REFUSE_VENDOR_ARGS" "unknown argument: $1" ;;
  esac
done

for p in "${FBLOB}" "${METALLIB}" "${BEAVER}" "${ANISO}" "${CLARET}" "${MANIFEST}"; do
  [[ -f "${p}" ]] || fail "GW_REFUSE_VENDOR_SOURCE_MISSING" "missing source file: ${p}"
done

mkdir -p "cells/franklin/avatar/bundle_assets/meshes"
mkdir -p "cells/franklin/avatar/bundle_assets/materials"
mkdir -p "cells/franklin/avatar/bundle_assets/spectral_luts"
mkdir -p "cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc"
mkdir -p "cells/franklin/avatar/bundle_assets/provenance"

cp "${FBLOB}" "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.fblob"
cp "${METALLIB}" "cells/franklin/avatar/bundle_assets/materials/Franklin_Z3_Materials.metallib"
cp "${BEAVER}" "cells/franklin/avatar/bundle_assets/spectral_luts/beaver_cap_spectral_lut.exr"
cp "${ANISO}" "cells/franklin/avatar/bundle_assets/spectral_luts/anisotropic_flow_map.exr"
cp "${CLARET}" "cells/franklin/avatar/bundle_assets/spectral_luts/claret_silk_degradation.exr"
cp "${MANIFEST}" "cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc/Manifest.json"

python3 - <<'PY' "${SOURCES}"
import json,sys,datetime,os
sources = [s.strip() for s in sys.argv[1].split(",") if s.strip()]
payload = {
  "timestamp_utc": datetime.datetime.utcnow().isoformat() + "Z",
  "source_registry_tags": sources,
  "staged_contract_files": [
    "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.fblob",
    "cells/franklin/avatar/bundle_assets/materials/Franklin_Z3_Materials.metallib",
    "cells/franklin/avatar/bundle_assets/spectral_luts/beaver_cap_spectral_lut.exr",
    "cells/franklin/avatar/bundle_assets/spectral_luts/anisotropic_flow_map.exr",
    "cells/franklin/avatar/bundle_assets/spectral_luts/claret_silk_degradation.exr",
    "cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc/Manifest.json",
  ],
}
out = "cells/franklin/avatar/bundle_assets/provenance/vendored_assets.json"
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
  json.dump(payload, f, indent=2)
PY

print "CALORIE:FRANKLIN-VENDOR:assets staged into in-repo contract paths"
