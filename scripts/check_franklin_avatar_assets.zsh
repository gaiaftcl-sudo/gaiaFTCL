#!/usr/bin/env zsh
# ══════════════════════════════════════════════════════════════════════════════
# check_franklin_avatar_assets.zsh
#
# Build-time gate. Reads the canonical required_assets.json and refuses if
# any asset is missing, undersized, or (when sha256 is pinned) hash-mismatched.
#
# Wired by:
#   • SwiftPM build-tool plugin (Plugins/CheckFranklinAvatarAssets/) so
#     `swift build` / `xcodebuild` fails before producing an .app that could
#     boot into the red FranklinLaunchRefusalView.
#   • CI / klein closure as a precondition.
#   • scripts/validate_franklin_avatar_fsd.sh as the canonical implementation.
#
# Exit codes:
#   0   all required assets present and valid
#   215 GW_REFUSE_ASSET_MISSING         (one or more files absent)
#   216 GW_REFUSE_ASSET_TOO_SMALL       (file size < min_bytes)
#   217 GW_REFUSE_ASSET_HASH_MISMATCH   (sha256 pinned and mismatched)
#   218 GW_REFUSE_FRANKLIN_VOICE_PROFILE_MISSING
#   219 GW_REFUSE_FRANKLIN_VOICE_PROFILE_INVALID_PERSONA
#   220 GW_REFUSE_AVATAR_WORKSPACE_ROOT_UNRESOLVED
#   221 GW_REFUSE_AVATAR_REQUIRED_ASSETS_JSON_MISSING
#
# Usage:
#   zsh scripts/check_franklin_avatar_assets.zsh [WORKSPACE_ROOT]
# ══════════════════════════════════════════════════════════════════════════════
set -o pipefail

WORKSPACE_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="${WORKSPACE_ROOT}/cells/franklin/avatar/required_assets.json"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'; NC=$'\033[0m'

emit_refusal() {
  print -u 2 "${RED}REFUSED:$1${NC}"
}

if [[ ! -d "${WORKSPACE_ROOT}" ]]; then
  emit_refusal "GW_REFUSE_AVATAR_WORKSPACE_ROOT_UNRESOLVED:${WORKSPACE_ROOT}"
  exit 220
fi

if [[ ! -f "${MANIFEST}" ]]; then
  emit_refusal "GW_REFUSE_AVATAR_REQUIRED_ASSETS_JSON_MISSING:${MANIFEST}"
  exit 221
fi

if ! command -v jq >/dev/null 2>&1; then
  print -u 2 "${YLW}WARN${NC} jq not found — install with brew install jq"
  exit 221
fi

# Returns the file size in bytes, or 0 if absent.
file_size() {
  local p="$1"
  if [[ ! -f "${p}" ]]; then print 0; return; fi
  /usr/bin/stat -f %z "${p}" 2>/dev/null || /usr/bin/stat -c %s "${p}" 2>/dev/null || print 0
}

# Returns sha256 hex digest of a file, or empty if absent.
file_sha256() {
  local p="$1"
  [[ -f "${p}" ]] || { print ""; return; }
  /usr/bin/shasum -a 256 "${p}" 2>/dev/null | /usr/bin/awk '{print $1}'
}

# Returns 0 if the file contains any forbidden placeholder substring.
# Scans the first 64 KB only — placeholders show their hand in the header.
file_has_placeholder_marker() {
  local p="$1"
  [[ -f "${p}" ]] || return 1
  local probe; probe="$(/usr/bin/head -c 65536 "${p}" 2>/dev/null)"
  [[ -z "${probe}" ]] && return 1
  local sub
  while IFS= read -r sub; do
    [[ -z "${sub}" ]] && continue
    if [[ "${probe}" == *"${sub}"* ]]; then
      print -r -- "${sub}"
      return 0
    fi
  done < <(jq -r '.forbidden_substrings[]? // empty' "${MANIFEST}")
  return 1
}

EXIT_RC=0
declare -a REFUSALS=()

# ─── pass 1: required_assets[] ───────────────────────────────────────────────
local count
count="$(jq -r '.required_assets | length' "${MANIFEST}")"
local i=0
while (( i < count )); do
  local label rel min_bytes pinned_sha
  label="$(jq -r ".required_assets[$i].label" "${MANIFEST}")"
  rel="$(jq -r ".required_assets[$i].relative_path" "${MANIFEST}")"
  min_bytes="$(jq -r ".required_assets[$i].min_bytes" "${MANIFEST}")"
  pinned_sha="$(jq -r ".required_assets[$i].sha256 // empty" "${MANIFEST}")"
  local abs="${WORKSPACE_ROOT}/${rel}"
  local size; size="$(file_size "${abs}")"
  if (( size == 0 )); then
    REFUSALS+=("GW_REFUSE_ASSET_MISSING:${label}")
    (( EXIT_RC == 0 )) && EXIT_RC=215
  elif (( size < min_bytes )); then
    REFUSALS+=("GW_REFUSE_ASSET_TOO_SMALL:${label} (${size}<${min_bytes})")
    (( EXIT_RC < 216 )) && EXIT_RC=216
  elif [[ -n "${pinned_sha}" ]]; then
    local actual; actual="$(file_sha256 "${abs}")"
    if [[ "${actual}" != "${pinned_sha}" ]]; then
      REFUSALS+=("GW_REFUSE_ASSET_HASH_MISMATCH:${label} (got=${actual:0:12}.. want=${pinned_sha:0:12}..)")
      (( EXIT_RC < 217 )) && EXIT_RC=217
    fi
  fi
  # Anti-placeholder enforcement (always on; cancer prevention):
  if [[ "$(jq -r '.forbid_placeholder_marker // false' "${MANIFEST}")" == "true" ]]; then
    local found
    if found="$(file_has_placeholder_marker "${abs}")"; then
      REFUSALS+=("GW_REFUSE_ASSET_PLACEHOLDER_MARKER:${label} (found:${found})")
      (( EXIT_RC < 222 )) && EXIT_RC=222
    fi
  fi
  (( i = i + 1 ))
done

# ─── pass 2: voice profile ──────────────────────────────────────────────────
local vp_path
vp_path="$(jq -r '.voice_profile.relative_path // empty' "${MANIFEST}")"
if [[ -n "${vp_path}" ]]; then
  local vp_abs="${WORKSPACE_ROOT}/${vp_path}"
  if [[ ! -f "${vp_abs}" ]]; then
    REFUSALS+=("GW_REFUSE_FRANKLIN_VOICE_PROFILE_MISSING:${vp_path}")
    (( EXIT_RC < 218 )) && EXIT_RC=218
  else
    local required_persona; required_persona="$(jq -r '.voice_profile.required_persona_id // empty' "${MANIFEST}")"
    local actual_persona; actual_persona="$(jq -r '.personaID // empty' "${vp_abs}" 2>/dev/null || print '')"
    if [[ -n "${required_persona}" ]] && [[ "${actual_persona}" != "${required_persona}" ]]; then
      REFUSALS+=("GW_REFUSE_FRANKLIN_VOICE_PROFILE_INVALID_PERSONA (got=${actual_persona} want=${required_persona})")
      (( EXIT_RC < 219 )) && EXIT_RC=219
    fi
  fi
fi

# ─── report ─────────────────────────────────────────────────────────────────
if (( EXIT_RC == 0 )); then
  print "${GRN}Franklin avatar asset gate: PASS${NC} (all $(jq -r '.required_assets | length' "${MANIFEST}") required assets present, sized, and (where pinned) hash-matched)"
  exit 0
fi

print -u 2 ""
print -u 2 "${RED}═══ Franklin avatar asset gate REFUSED ═══${NC}"
print -u 2 "${RED}   The build will not produce a FranklinApp binary while these refusals stand.${NC}"
print -u 2 "${RED}   Repair each refusal under cells/franklin/avatar/bundle_assets/ and re-run the build.${NC}"
print -u 2 ""
for r in "${REFUSALS[@]}"; do
  print -u 2 "  ${RED}REFUSED:${r}${NC}"
done
print -u 2 ""
exit "${EXIT_RC}"
