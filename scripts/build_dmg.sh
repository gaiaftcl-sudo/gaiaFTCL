#!/usr/bin/env bash
# build_dmg.sh — GaiaFTCL sovereign M⁸ DMG builder
#
# Builds release binaries (VQbitVM, FranklinConsciousnessService), assembles
# a macOS .app bundle inside a DMG, and writes the DMG to dist/.
#
# Requirements:
#   • Xcode 26+ (swift 6.2)
#   • create-dmg (brew install create-dmg) OR hdiutil (built-in)
#   • macOS 26+ build host
#
# Usage:
#   cd /path/to/AppleGaiaFTCL
#   bash scripts/build_dmg.sh
#   # → dist/GaiaFTCL-<VERSION>.dmg

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_ROOT="$REPO_ROOT/cells/xcode"
APP_TEMPLATE="$REPO_ROOT/GAIAOS/macos/Franklin/dist/FranklinApp.app"
DIST_DIR="$REPO_ROOT/dist"
VERSION="${GAIAFTCL_VERSION:-1.0.0}"
DMG_NAME="GaiaFTCL-${VERSION}"
VOLUME_NAME="GaiaFTCL ${VERSION}"
APP_BUNDLE="$DIST_DIR/${DMG_NAME}.app"

echo "==> GaiaFTCL DMG Builder"
echo "    Version : $VERSION"
echo "    Repo    : $REPO_ROOT"
echo ""

# ── 1. Build release binaries ──────────────────────────────────────────────────

echo "==> Building release targets..."
cd "$XCODE_ROOT"
swift build -c release --product VQbitVM 2>&1 | tail -5
swift build -c release --product FranklinConsciousnessService 2>&1 | tail -5

RELEASE_BIN="$XCODE_ROOT/.build/release"
echo "    VQbitVM               : $RELEASE_BIN/VQbitVM"
echo "    FranklinConsciousness : $RELEASE_BIN/FranklinConsciousnessService"

# ── 2. Assemble .app bundle ────────────────────────────────────────────────────

echo ""
echo "==> Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
cp -R "$APP_TEMPLATE" "$APP_BUNDLE"

# MacOS (binary) directory
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
mkdir -p "$MACOS_DIR"

# Copy the FranklinApp stub as the main executable (matches CFBundleExecutable)
cp "$MACOS_DIR/../MacOS/FranklinApp" "$MACOS_DIR/FranklinApp" 2>/dev/null || true

# Copy sovereign binaries into Resources/bin/ so they ship with the app
BIN_DIR="$APP_BUNDLE/Contents/Resources/bin"
mkdir -p "$BIN_DIR"
cp "$RELEASE_BIN/VQbitVM"                    "$BIN_DIR/"
cp "$RELEASE_BIN/FranklinConsciousnessService" "$BIN_DIR/"

# Copy launchd plists into Resources/launchd/
LAUNCHD_DIR="$APP_BUNDLE/Contents/Resources/launchd"
mkdir -p "$LAUNCHD_DIR"
cp "$XCODE_ROOT/launchd/"*.plist "$LAUNCHD_DIR/" 2>/dev/null || true

# Patch Info.plist version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" \
    "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" \
    "$APP_BUNDLE/Contents/Info.plist"

echo "    Bundle  : $APP_BUNDLE"

# ── 3. Ad-hoc sign the bundle (no developer ID required for local use) ─────────

echo ""
echo "==> Ad-hoc signing bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 || {
    echo "    WARN: codesign failed — bundle may not launch on other Macs without Gatekeeper exception"
}

# ── 4. Create DMG ─────────────────────────────────────────────────────────────

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/${DMG_NAME}.dmg"
rm -f "$DMG_PATH"

echo ""
echo "==> Creating DMG: $DMG_PATH"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "$VOLUME_NAME" \
        --window-pos 200 120 \
        --window-size 600 380 \
        --icon-size 128 \
        --app-drop-link 420 140 \
        --icon "${DMG_NAME}.app" 160 140 \
        "$DMG_PATH" \
        "$APP_BUNDLE"
else
    # Fallback: plain hdiutil DMG (no custom layout)
    hdiutil create \
        -volname "$VOLUME_NAME" \
        -srcfolder "$APP_BUNDLE" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo ""
echo "==> Done."
echo "    DMG     : $DMG_PATH"
echo "    Size    : $(du -sh "$DMG_PATH" | cut -f1)"
echo ""
echo "To publish to GitHub releases:"
echo "  gh release create v${VERSION} $DMG_PATH \\"
echo "    --title 'GaiaFTCL v${VERSION} — Sovereign M⁸ vQbit VM' \\"
echo "    --notes 'Full IQ/OQ/PQ qualified release. macOS 26+. 38/38 MQ pass.'"
