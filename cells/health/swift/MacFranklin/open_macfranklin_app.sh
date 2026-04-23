#!/usr/bin/env zsh
# Build MacFranklin.app and open it — terminal-visible proof (see ADDON_APP_VISIBLE_PROOF.md).
# Usage from repo root:
#   zsh cells/health/swift/MacFranklin/open_macfranklin_app.sh
set -euo pipefail
HERE="${0:a:h}"
cd "$HERE"

# Repo root: .../cells/health/swift/MacFranklin -> five levels up = gaiaFTCL root (cells/health/swift/MacFranklin -> 4 up to repo? count: MacFranklin=0, swift=1, health=2, cells=3, REPO=4)
_REPO="${HERE}/../../../.."
_REPO="${_REPO:A}"
export GAIAFTCL_REPO_ROOT="${GAIAFTCL_REPO_ROOT:-$_REPO}"
export GAIAHEALTH_REPO_ROOT="${GAIAHEALTH_REPO_ROOT:-$GAIAFTCL_REPO_ROOT}"

echo "============================================================"
echo "MacFranklin ADDON — visible build + open"
echo "============================================================"
echo "GAIAFTCL_REPO_ROOT=$GAIAFTCL_REPO_ROOT"
if [[ ! -f "$GAIAFTCL_REPO_ROOT/cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh" ]]; then
  echo "REFUSED: repo root does not look like FoT8D / gaiaFTCL (missing franklin driver)." >&2
  exit 1
fi

echo ""
echo "== swift build (release) + bundle =="
zsh "$HERE/build_macfranklin_app.sh"

APP="$HERE/.build/MacFranklin.app"
echo ""
echo "APP_PATH=$APP"
if [[ ! -d "$APP" ]]; then
  echo "REFUSED: expected app bundle missing: $APP" >&2
  exit 1
fi

echo ""
echo "== open (macOS GUI) =="
if [[ -n "${SSH_CONNECTION:-}" ]] && [[ "${MACFRANKLIN_OPEN_APP:-1}" != "0" ]]; then
  echo "Note: SSH session detected. If no window appears, run this script on the Mac console or set MACFRANKLIN_OPEN_APP=0 to skip open."
fi
if command -v open >/dev/null 2>&1; then
  open "$APP"
  echo "OK: open issued for MacFranklin.app — check Dock / Cmd-Tab."
else
  echo "REFUSED: no 'open' command (not macOS?)" >&2
  exit 2
fi
echo "OK: script complete."
