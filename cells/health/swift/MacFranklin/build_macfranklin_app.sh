#!/usr/bin/env zsh
# Build MacFranklin executable (SwiftPM) and assemble MacFranklin.app in .build/ bundle dir.
# Usage: from repo root:
#   zsh cells/health/swift/MacFranklin/build_macfranklin_app.sh
set -euo pipefail
HERE="${0:a:h}"
cd "$HERE"

swift build -c release
BP="$(swift build -c release --show-bin-path)"
BIN="$BP/MacFranklin"
test -x "$BIN" || { echo "REFUSED: no binary at $BIN" >&2; exit 1; }
RESB="$BP/MacFranklin_MacFranklin.bundle"
test -d "$RESB" || { echo "REFUSED: missing resource bundle (Franklin usda): $RESB" >&2; exit 1; }

APP_DIR="$HERE/.build/MacFranklin.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/MacFranklin"
chmod +x "$APP_DIR/Contents/MacOS/MacFranklin"
# SwiftPM: Bundle.module resolves the resource bundle next to the executable
cp -R "$RESB" "$APP_DIR/Contents/MacOS/"
cp -R "$RESB" "$APP_DIR/Contents/Resources/"

# Minimal Info.plist
if [[ ! -f "$APP_DIR/Contents/Info.plist" ]]; then
  cat > "$APP_DIR/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacFranklin</string>
  <key>CFBundleIdentifier</key>
  <string>com.fortressai.gaiaftcl.MacFranklin</string>
  <key>CFBundleName</key>
  <string>MacFranklin</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PL
fi

echo "Built: $APP_DIR"
echo "Open with: open \"$APP_DIR\""
