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
  c=$(ls "${dir}"/*.json 2>/dev/null | wc -l | tr -d ' ')
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

# TSD-MAC-001
[[ -f "GAIAOS/macos/Franklin/Package.swift" ]] || fail "GW_REFUSE_TSD_MAC_001" "missing Franklin Package.swift" 101
[[ -f "GAIAOS/macos/Franklin/Sources/FranklinApp/FranklinApp.swift" ]] || fail "GW_REFUSE_TSD_MAC_001" "missing FranklinApp.swift" 101
[[ -f "GAIAOS/macos/Franklin/Sources/FranklinApp/OperatorSurfaceModel.swift" ]] || fail "GW_REFUSE_TSD_MAC_001" "missing OperatorSurfaceModel.swift" 101

# TSD-MAC-002
[[ -f "cells/franklin/avatar/Cargo.toml" ]] || fail "GW_REFUSE_TSD_MAC_002" "missing Franklin avatar workspace Cargo.toml" 102
for crate in avatar-core avatar-tts avatar-render avatar-bridge avatar-runtime; do
  [[ -f "cells/franklin/avatar/crates/${crate}/Cargo.toml" ]] || fail "GW_REFUSE_TSD_MAC_002" "missing crate ${crate}" 102
done

# TSD-MAC-003
illum="$(json_count "cells/franklin/avatar/bundle_assets/illuminants")"
viseme="$(json_count "cells/franklin/avatar/bundle_assets/pose_templates/viseme")"
expr="$(json_count "cells/franklin/avatar/bundle_assets/pose_templates/expression")"
posture="$(json_count "cells/franklin/avatar/bundle_assets/pose_templates/posture")"
(( illum >= 4 )) || fail "GW_REFUSE_TSD_MAC_003" "illuminants<4" 103
(( viseme >= 11 )) || fail "GW_REFUSE_TSD_MAC_003" "viseme<11" 103
(( expr >= 12 )) || fail "GW_REFUSE_TSD_MAC_003" "expression<12" 103
(( posture >= 6 )) || fail "GW_REFUSE_TSD_MAC_003" "posture<6" 103
mesh_exists || fail "GW_REFUSE_TSD_MAC_003" "missing Passy mesh asset (usdz/usda/usdc/obj/gltf/glb)" 103

# TSD-MAC-004
[[ -f "cells/fusion/macos/GaiaFusion/Package.swift" ]] || fail "GW_REFUSE_TSD_MAC_004" "missing GaiaFusion Package.swift" 104
[[ -f "cells/fusion/macos/GaiaFusion/GaiaFusion/GaiaFusionApp.swift" ]] || fail "GW_REFUSE_TSD_MAC_004" "missing GaiaFusionApp.swift" 104
[[ -f "cells/fusion/macos/GaiaFusion/MetalRenderer/rust/Cargo.toml" ]] || fail "GW_REFUSE_TSD_MAC_004" "missing GaiaFusion renderer rust Cargo.toml" 104
[[ -f "cells/fusion/macos/GaiaFusion/MetalRenderer/include/gaia_metal_renderer.h" ]] || fail "GW_REFUSE_TSD_MAC_004" "missing GaiaFusion renderer header" 104
[[ -f "cells/fusion/macos/GaiaFusion/MetalRenderer/lib/libgaia_metal_renderer.a" ]] || fail "GW_REFUSE_TSD_MAC_004" "missing GaiaFusion renderer static lib" 104

# TSD-MAC-005
[[ -f "cells/fusion/macos/MacHealth/Package.swift" ]] || fail "GW_REFUSE_TSD_MAC_005" "missing MacHealth Package.swift" 105
[[ -f "cells/health/Cargo.toml" ]] || fail "GW_REFUSE_TSD_MAC_005" "missing cells/health Cargo.toml" 105
[[ -f "cells/health/gaia-health-renderer/src/lib.rs" ]] || fail "GW_REFUSE_TSD_MAC_005" "missing gaia-health-renderer/src/lib.rs" 105
[[ -f "cells/health/biologit_md_engine/src/lib.rs" ]] || fail "GW_REFUSE_TSD_MAC_005" "missing biologit_md_engine/src/lib.rs" 105

# TSD-MAC-006
[[ -f "cells/lithography/docs/IQ_OQ_PQ_LITHOGRAPHY_CELL.md" ]] || fail "GW_REFUSE_TSD_MAC_006" "missing IQ_OQ_PQ_LITHOGRAPHY_CELL.md" 106
[[ -f "cells/lithography/docs/GAMP5_LIFECYCLE.md" ]] || fail "GW_REFUSE_TSD_MAC_006" "missing lithography GAMP5_LIFECYCLE.md" 106
[[ -f "cells/lithography/docs/FUNCTIONAL_SPECIFICATION.md" ]] || fail "GW_REFUSE_TSD_MAC_006" "missing lithography FUNCTIONAL_SPECIFICATION.md" 106
[[ -f "cells/franklin/docs/LITHOGRAPHY_MAC_PATH.md" ]] || fail "GW_REFUSE_TSD_MAC_006" "missing LITHOGRAPHY_MAC_PATH.md" 106
[[ -f "wiki/M8_Lithography_Silicon_Cell_Wiki.md" ]] || fail "GW_REFUSE_TSD_MAC_006" "missing M8_Lithography_Silicon_Cell_Wiki.md" 106
[[ -f "wiki/Qualification-Catalog.md" ]] || fail "GW_REFUSE_TSD_MAC_006" "missing Qualification-Catalog.md" 106

print "CALORIE:TSD-MAC-STACKS:all contracts satisfied"
