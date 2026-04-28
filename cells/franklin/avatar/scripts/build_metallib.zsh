#!/usr/bin/env zsh
# ══════════════════════════════════════════════════════════════════════════════
# build_metallib.zsh
#
# Compiles cells/franklin/avatar/shaders/*.metal into the production
# Franklin_Z3_Materials.metallib that the asset gate requires.
#
# This is the ONLY supported way to produce the .metallib. The gate refuses
# any binary carrying placeholder/dev_stub markers. There is no stub mode.
#
# Required tools (refuses if absent):
#   xcrun metal      (Metal compiler — Xcode 15+)
#   xcrun metallib   (linker)
#
# Usage:  zsh cells/franklin/avatar/scripts/build_metallib.zsh
# ══════════════════════════════════════════════════════════════════════════════
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AVATAR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHADER_DIR="${AVATAR_DIR}/shaders"
BUILD_DIR="${AVATAR_DIR}/build/metallib"
OUT_DIR="${AVATAR_DIR}/bundle_assets/materials"
OUT="${OUT_DIR}/Franklin_Z3_Materials.metallib"
RECEIPT="${AVATAR_DIR}/build/metallib_provenance.json"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; NC=$'\033[0m'
emit_refusal() { print -u 2 "${RED}REFUSED:$1${NC}"; }

# Toolchain floor — refuse honestly when missing.
if ! command -v xcrun >/dev/null 2>&1; then
  emit_refusal "GW_REFUSE_PIPELINE_TOOLCHAIN_MISSING:xcrun (install Xcode 15+ command-line tools)"
  exit 230
fi
if ! xcrun --find metal >/dev/null 2>&1; then
  emit_refusal "GW_REFUSE_PIPELINE_TOOLCHAIN_MISSING:metal (xcrun --find metal failed)"
  exit 231
fi
if ! xcrun --find metallib >/dev/null 2>&1; then
  emit_refusal "GW_REFUSE_PIPELINE_TOOLCHAIN_MISSING:metallib"
  exit 232
fi

mkdir -p "${BUILD_DIR}" "${OUT_DIR}" "$(dirname "${RECEIPT}")"
setopt local_options null_glob
rm -f "${BUILD_DIR}"/*.air "${OUT}" "${RECEIPT}" 2>/dev/null

# Sources in the order they must compile. Common.metal is a header included
# via #include; not compiled directly. Pass shaders compile to .air objects.
typeset -a SRCS=(
  "pass1_geometry.metal"
  "pass2_shadow.metal"
  "pass3_pbd_cloth.metal"
  "pass4_strand_fur.metal"
  "pass5_lit_spectral.metal"
  "pass6_refusal_banner.metal"
  "pass7_tonemap.metal"
)

# Verify every source exists before we start (so a partial run cannot ship).
for src in "${SRCS[@]}"; do
  [[ -f "${SHADER_DIR}/${src}" ]] || {
    emit_refusal "GW_REFUSE_PIPELINE_SHADER_SOURCE_MISSING:${src}"
    exit 233
  }
done

# Compile each .metal → .air against macOS Metal 3.0+. -ffast-math is
# permitted because spectral integration is dominated by smooth transcendentals
# already; we don't rely on strict NaN handling in any shader.
typeset -a AIRS=()
for src in "${SRCS[@]}"; do
  base="${src%.metal}"
  air="${BUILD_DIR}/${base}.air"
  print "${YLW}metal -c${NC} ${src}"
  xcrun -sdk macosx metal \
    -c "${SHADER_DIR}/${src}" \
    -I "${SHADER_DIR}" \
    -o "${air}" \
    -std=metal3.0 \
    -ffast-math \
    || { emit_refusal "GW_REFUSE_PIPELINE_METAL_COMPILE_FAILED:${src}"; exit 234 }
  AIRS+=("${air}")
done

# Link the .air objects into the production .metallib.
print "${YLW}metallib${NC} → ${OUT}"
xcrun -sdk macosx metallib "${AIRS[@]}" -o "${OUT}" \
  || { emit_refusal "GW_REFUSE_PIPELINE_METALLIB_LINK_FAILED"; exit 235 }

# Provenance receipt: declare exactly which sources produced the .metallib so
# the FUIT signer can attach a real provenance entry instead of a placeholder.
typeset src_hashes='[]'
for src in "${SRCS[@]}"; do
  h="$(/usr/bin/shasum -a 256 "${SHADER_DIR}/${src}" | /usr/bin/awk '{print $1}')"
  src_hashes="$(jq --arg s "${src}" --arg h "${h}" '. + [{source: $s, sha256: $h}]' <<< "${src_hashes}")"
done
out_sha="$(/usr/bin/shasum -a 256 "${OUT}" | /usr/bin/awk '{print $1}')"
jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg out "${OUT}" \
  --arg out_sha "${out_sha}" \
  --argjson srcs "${src_hashes}" \
  '{schema:"GFTCL-AVATAR-METALLIB-PROVENANCE-001",ts:$ts,output_path:$out,output_sha256:$out_sha,sources:$srcs,placeholder:false,produced_by:"build_metallib.zsh"}' \
  > "${RECEIPT}"

print "${GRN}metallib produced:${NC} ${OUT}"
print "  size:    $(/usr/bin/stat -f %z "${OUT}" 2>/dev/null || /usr/bin/stat -c %s "${OUT}") bytes"
print "  sha256:  ${out_sha}"
print "  receipt: ${RECEIPT}"
