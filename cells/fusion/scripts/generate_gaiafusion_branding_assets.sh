#!/usr/bin/env bash
# Generate AppIcon.icns + splash ImageSet PNGs from committed masters under cells/fusion/assets/branding/
# (optional fallback: macos/GaiaFusion/Branding/sources/). Idempotent; run before swift build / package.
# C4: no ~/Downloads or other out-of-repo inputs — paths must resolve under GAIAOS ROOT.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEGACY_SRC="$ROOT/macos/GaiaFusion/Branding/sources"
CANONICAL_SRC="$ROOT/assets/branding"
SRC="${GAIAFUSION_BRANDING_SOURCES:-$CANONICAL_SRC}"
OUT="$ROOT/macos/GaiaFusion/GaiaFusion/Resources/Branding"
ICONSET_OUT="$ROOT/macos/GaiaFusion/Branding/generated/AppIcon.iconset"
LOG_LABEL="[generate_gaiafusion_branding_assets]"

require_under_repo() {
  local abs
  abs="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  case "$abs" in
    "$ROOT"/*) return 0 ;;
    *)
      echo "$LOG_LABEL REFUSED: path must be under repo ROOT ($ROOT): $1" >&2
      return 1
      ;;
  esac
}

if [[ ! -d "$SRC" ]] && [[ -d "$CANONICAL_SRC" ]]; then
  SRC="$CANONICAL_SRC"
fi
if [[ ! -d "$SRC" ]] && [[ -d "$LEGACY_SRC" ]]; then
  SRC="$LEGACY_SRC"
fi

require_under_repo "$SRC" || exit 1

pick_master() {
  local primary="$1"
  local alt="$2"
  if [[ -f "$SRC/$primary" ]]; then
    echo "$SRC/$primary"
  elif [[ -f "$SRC/$alt" ]]; then
    echo "$SRC/$alt"
  else
    echo ""
  fi
}

ICON_MASTER="$(pick_master app_icon_master.png Icon.png)"
SPLASH_MASTER="$(pick_master splash_master.png Splash.png)"

if [[ -z "$ICON_MASTER" || ! -f "$ICON_MASTER" ]]; then
  echo "$LOG_LABEL REFUSED: missing icon master — place app_icon_master.png or Icon.png in $SRC" >&2
  exit 1
fi
if [[ -z "$SPLASH_MASTER" || ! -f "$SPLASH_MASTER" ]]; then
  echo "$LOG_LABEL REFUSED: missing splash master — place splash_master.png or Splash.png in $SRC" >&2
  exit 1
fi

require_under_repo "$ICON_MASTER" || exit 1
require_under_repo "$SPLASH_MASTER" || exit 1

mkdir -p "$ICONSET_OUT" "$OUT/Splash.imageset"

# macOS iconset (iconutil). Sizes in points @1x and @2x for 16,32,128,256,512
declare -a PAIRS=(
  "16 icon_16x16.png"
  "32 icon_16x16@2x.png"
  "32 icon_32x32.png"
  "64 icon_32x32@2x.png"
  "128 icon_128x128.png"
  "256 icon_128x128@2x.png"
  "256 icon_256x256.png"
  "512 icon_256x256@2x.png"
  "512 icon_512x512.png"
  "1024 icon_512x512@2x.png"
)

for row in "${PAIRS[@]}"; do
  px="${row%% *}"
  name="${row#* }"
  /usr/bin/sips -z "$px" "$px" "$ICON_MASTER" --out "$ICONSET_OUT/$name" >/dev/null
done

cat >"$ICONSET_OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16@2x.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32@2x.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
JSON

/usr/bin/iconutil -c icns "$ICONSET_OUT" -o "$OUT/AppIcon.icns"

# Splash @1x / @2x for wide window (approx 1200x800 base)
/usr/bin/sips -z 800 1200 "$SPLASH_MASTER" --out "$OUT/Splash.imageset/splash@1x.png" >/dev/null
/usr/bin/sips -z 1600 2400 "$SPLASH_MASTER" --out "$OUT/Splash.imageset/splash@2x.png" >/dev/null
cat >"$OUT/Splash.imageset/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "filename" : "splash@1x.png", "scale" : "1x" },
    { "idiom" : "universal", "filename" : "splash@2x.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "gaiaftcl" }
}
JSON

echo "$LOG_LABEL CALORIE: $OUT/AppIcon.icns + Splash.imageset (iconset: $ICONSET_OUT) SRC=$SRC"
ls -la "$OUT/AppIcon.icns" "$OUT/Splash.imageset"/*.png
