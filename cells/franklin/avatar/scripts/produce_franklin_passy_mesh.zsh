#!/usr/bin/env zsh
# ══════════════════════════════════════════════════════════════════════════════
# produce_franklin_passy_mesh.zsh
#
# Production pipeline for Franklin_Passy_V2.fblob — the only supported way
# to produce the required mesh asset. No stubs, no placeholders.
#
# Inputs (the operator must supply these from the real 3D pipeline):
#   cells/franklin/avatar/bundle_assets/meshes/sources/Franklin_Passy_V2.usdz
#     — Master USDZ from Joseph-Siffred Duplessis 1778 photogrammetry,
#       retopologized to ~1.5M tris with an ARKit FACS-52 blendshape rig.
#       Must include: head, neck, shoulders, beaver-fur cap (separate mesh),
#       tied-back hair guides, two-piece spectacles, frock coat with cravat
#       loop, and FACS-52 blendshapes (jawOpen, mouthSmileLeft/Right,
#       eyeBlinkLeft/Right, browInnerUp, etc.).
#
# Tool floor (refuses if absent):
#   tools/bake_mesh/  (the avatar-core bake_mesh Rust binary)
#   xcrun usdtool     (USD validation)
#
# Output:
#   cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.fblob
#   cells/franklin/avatar/build/mesh_provenance.json
#
# Usage: zsh cells/franklin/avatar/scripts/produce_franklin_passy_mesh.zsh
# ══════════════════════════════════════════════════════════════════════════════
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AVATAR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${AVATAR_DIR}/../../.." && pwd)"
SRC_USDZ="${AVATAR_DIR}/bundle_assets/meshes/sources/Franklin_Passy_V2.usdz"
OUT_FBLOB="${AVATAR_DIR}/bundle_assets/meshes/Franklin_Passy_V2.fblob"
RECEIPT="${AVATAR_DIR}/build/mesh_provenance.json"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; NC=$'\033[0m'
emit_refusal() { print -u 2 "${RED}REFUSED:$1${NC}"; }

# Tool floor.
BAKE_BIN="${REPO_ROOT}/tools/bake_mesh/target/release/bake_mesh"
if [[ ! -x "${BAKE_BIN}" ]]; then
  # try host-tools prebuilt path used by sprout
  BAKE_BIN="${AVATAR_DIR}/host-tools/darwin-arm64/bake_mesh"
fi
if [[ ! -x "${BAKE_BIN}" ]]; then
  emit_refusal "GW_REFUSE_PIPELINE_TOOLCHAIN_MISSING:bake_mesh (build with cargo build --release --manifest-path tools/bake_mesh/Cargo.toml)"
  exit 240
fi

# Input acceptance criteria.
if [[ ! -f "${SRC_USDZ}" ]]; then
  emit_refusal "GW_REFUSE_PIPELINE_INPUT_MISSING:${SRC_USDZ#${REPO_ROOT}/}"
  print -u 2 ""
  print -u 2 "${YLW}This script does not author the master USDZ. The artist pipeline must:${NC}"
  print -u 2 "  1. Photogrammetry-scan a high-fidelity 3D bust from the Duplessis 1778"
  print -u 2 "     reference (or equivalent Passy-period reference)."
  print -u 2 "  2. Retopologize to ≈1.5M tris with consistent UVs."
  print -u 2 "  3. Author the FACS-52 ARKit blendshape rig in Maya/Houdini/Blender."
  print -u 2 "  4. Include separate meshes for: head+neck, beaver-fur cap, frock coat,"
  print -u 2 "     cravat lace, spectacles."
  print -u 2 "  5. Export as USDZ to ${SRC_USDZ#${REPO_ROOT}/}."
  print -u 2 "  6. Run this script."
  print -u 2 ""
  exit 241
fi

src_size="$(/usr/bin/stat -f %z "${SRC_USDZ}" 2>/dev/null || /usr/bin/stat -c %s "${SRC_USDZ}")"
if (( src_size < 5000000 )); then
  emit_refusal "GW_REFUSE_PIPELINE_INPUT_TOO_SMALL:Franklin_Passy_V2.usdz (${src_size} < 5MB threshold; not a real Passy mesh)"
  exit 242
fi

# Bake.
print "${YLW}bake_mesh${NC} ${SRC_USDZ#${REPO_ROOT}/} → ${OUT_FBLOB#${REPO_ROOT}/}"
mkdir -p "$(dirname "${OUT_FBLOB}")" "$(dirname "${RECEIPT}")"
"${BAKE_BIN}" \
  --input "${SRC_USDZ}" \
  --output "${OUT_FBLOB}" \
  --target-tris 1500000 \
  --required-blendshapes 52 \
  --refuse-placeholder \
  || { emit_refusal "GW_REFUSE_PIPELINE_BAKE_MESH_FAILED"; exit 243 }

# Provenance receipt.
out_size="$(/usr/bin/stat -f %z "${OUT_FBLOB}" 2>/dev/null || /usr/bin/stat -c %s "${OUT_FBLOB}")"
out_sha="$(/usr/bin/shasum -a 256 "${OUT_FBLOB}" | /usr/bin/awk '{print $1}')"
src_sha="$(/usr/bin/shasum -a 256 "${SRC_USDZ}" | /usr/bin/awk '{print $1}')"
jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg src "${SRC_USDZ#${REPO_ROOT}/}" \
  --arg src_sha "${src_sha}" \
  --arg out "${OUT_FBLOB#${REPO_ROOT}/}" \
  --arg out_sha "${out_sha}" \
  --argjson out_size "${out_size}" \
  '{schema:"GFTCL-AVATAR-MESH-PROVENANCE-001",ts:$ts,source_usdz:$src,source_sha256:$src_sha,output_fblob:$out,output_sha256:$out_sha,output_size_bytes:$out_size,placeholder:false}' \
  > "${RECEIPT}"

print "${GRN}mesh produced:${NC} ${OUT_FBLOB}"
print "  size:    ${out_size} bytes"
print "  sha256:  ${out_sha}"
print "  receipt: ${RECEIPT}"
