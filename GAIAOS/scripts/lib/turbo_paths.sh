# Resolve GAIA repo / volume root for Turbo IDE and DMG-relative tools.
# Usage: source this file then call turbo_resolve_gaia_root "$0"

turbo_resolve_gaia_root() {
  local self="${1:-$0}"
  local d vol three
  d="$(cd "$(dirname "$self")" && pwd)"
  if [[ -n "${GAIA_ROOT:-}" ]]; then
    printf '%s\n' "${GAIA_ROOT}"
    return
  fi
  if [[ "$d" == */scripts ]]; then
    cd "$d/.." && pwd
    return
  fi
  vol="$(cd "$d/.." && pwd)"
  three="$(cd "$d/../../.." && pwd)"
  if [[ -f "$vol/deploy/fusion_mesh/fusion_projection.json" ]]; then
    printf '%s\n' "$vol"
  elif [[ -f "$three/deploy/fusion_mesh/fusion_projection.json" ]]; then
    printf '%s\n' "$three"
  elif [[ -d "$vol/scripts" && -f "$vol/scripts/fusion_turbo_ide.sh" ]]; then
    printf '%s\n' "$vol"
  elif [[ -d "$three/scripts" ]]; then
    printf '%s\n' "$three"
  else
    printf '%s\n' "$vol"
  fi
}

# For bridges under bin/: volume root or GAIAOS (deploy/mac_cell_mount/bin → three levels up).
turbo_resolve_root_from_bin() {
  local here vol three
  here="$(cd "$(dirname "${1:-$0}")" && pwd)"
  vol="$(cd "$here/.." && pwd)"
  three="$(cd "$here/../../.." && pwd)"
  if [[ -f "$vol/deploy/fusion_mesh/fusion_projection.json" ]]; then
    printf '%s\n' "$vol"
  elif [[ -f "$three/deploy/fusion_mesh/fusion_projection.json" ]]; then
    printf '%s\n' "$three"
  else
    printf '%s\n' "$vol"
  fi
}
