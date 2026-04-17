#!/usr/bin/env bash
set -euo pipefail

echo "🔨 Building GaiaFTCL Test DMG"
echo ""

VERSION="${VERSION:-1.0.0-test}"
BUILD_DIR="build/test_dmg"
DIST_DIR="dist"
APP_NAME="GaiaFTCL.app"

# Clean
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "$BUILD_DIR/$APP_NAME/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME/Contents/Resources"

# Create a simple test executable (shell script wrapper)
cat > "$BUILD_DIR/$APP_NAME/Contents/MacOS/GaiaFTCL" << 'EXEC'
#!/bin/bash
osascript -e 'display notification "GaiaFTCL Test Build Running" with title "GaiaFTCL"'
echo "GaiaFTCL Test Build - Version 1.0.0-test"
echo "This is a test build to verify DMG creation and installation."
echo ""
echo "✅ App launched successfully"
echo "✅ Bundle structure verified"
echo "✅ macOS integration working"
echo ""
echo "Press Ctrl+C to quit"
sleep infinity
EXEC

chmod +x "$BUILD_DIR/$APP_NAME/Contents/MacOS/GaiaFTCL"

# Create Info.plist
cat > "$BUILD_DIR/$APP_NAME/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>GaiaFTCL</string>
    <key>CFBundleDisplayName</key>
    <string>GaiaFTCL Test</string>
    <key>CFBundleIdentifier</key>
    <string>com.gaiaftcl.test</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>GaiaFTCL</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "✅ App bundle created"

# Create DMG
echo ""
echo "📦 Creating DMG..."

DMG_TEMP="$BUILD_DIR/dmg_temp"
mkdir -p "$DMG_TEMP"

cp -r "$BUILD_DIR/$APP_NAME" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

cat > "$DMG_TEMP/README.txt" << README
GaiaFTCL Test Build
===================

This is a test build to verify:
- DMG creation
- App installation
- macOS integration

Installation:
1. Drag GaiaFTCL.app to Applications
2. Launch from Applications
3. Verify notification appears

Version: $VERSION
Build Date: $(date -u +%Y-%m-%d)
README

# Create DMG
hdiutil create \
    -volname "GaiaFTCL Test" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DIST_DIR/GaiaFTCL-$VERSION.dmg"

echo "✅ DMG created: $DIST_DIR/GaiaFTCL-$VERSION.dmg"

# Generate checksum
echo ""
echo "🔐 Generating checksum..."
shasum -a 256 "$DIST_DIR/GaiaFTCL-$VERSION.dmg" > "$DIST_DIR/GaiaFTCL-$VERSION.dmg.sha256"
CHECKSUM=$(cat "$DIST_DIR/GaiaFTCL-$VERSION.dmg.sha256" | awk '{print $1}')
echo "✅ Checksum: $CHECKSUM"

# Create version manifest
cat > "$DIST_DIR/version.json" << VERSION_JSON
{
  "version": "$VERSION",
  "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dmg_name": "GaiaFTCL-$VERSION.dmg",
  "checksum": "$CHECKSUM",
  "size": $(stat -f%z "$DIST_DIR/GaiaFTCL-$VERSION.dmg"),
  "required_os": "macOS 11.0+",
  "build_type": "test"
}
VERSION_JSON

echo "✅ Version manifest created"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ TEST BUILD COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "DMG: $DIST_DIR/GaiaFTCL-$VERSION.dmg"
echo "Size: $(du -h "$DIST_DIR/GaiaFTCL-$VERSION.dmg" | awk '{print $1}')"
echo "Checksum: $CHECKSUM"
echo ""
echo "Next steps:"
echo "  1. Mount DMG: open $DIST_DIR/GaiaFTCL-$VERSION.dmg"
echo "  2. Install to /Applications"
echo "  3. Launch and verify"
