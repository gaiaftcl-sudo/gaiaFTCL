#!/bin/bash
# GaiaFusion .app Bundle Builder
# Creates distributable macOS application bundle

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build/arm64-apple-macosx/release"
APP_NAME="GaiaFusion"
APP_BUNDLE="$PROJECT_ROOT/${APP_NAME}.app"
VERSION="1.0.0-beta.1"
BUILD_NUMBER="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

echo "🚀 Building ${APP_NAME}.app bundle..."
echo "   Version: $VERSION"
echo "   Build: $BUILD_NUMBER"

# Clean previous bundle
if [ -d "$APP_BUNDLE" ]; then
    echo "🧹 Removing existing bundle..."
    rm -rf "$APP_BUNDLE"
fi

# Create bundle structure
echo "📦 Creating bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy binary
echo "📋 Copying release binary..."
if [ ! -f "$BUILD_DIR/$APP_NAME" ]; then
    echo "❌ ERROR: Release binary not found at $BUILD_DIR/$APP_NAME"
    echo "   Run: swift build --configuration release --product GaiaFusion"
    exit 1
fi
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy resources
echo "📂 Copying resources..."

# Fusion web UI (Next.js)
if [ -d "$PROJECT_ROOT/GaiaFusion/Resources/fusion-web" ]; then
    cp -R "$PROJECT_ROOT/GaiaFusion/Resources/fusion-web" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ fusion-web/"
else
    echo "   ⚠️  fusion-web/ not found"
fi

# Metal library
if [ -f "$PROJECT_ROOT/GaiaFusion/Resources/default.metallib" ]; then
    cp "$PROJECT_ROOT/GaiaFusion/Resources/default.metallib" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ default.metallib"
else
    echo "   ⚠️  default.metallib not found"
fi

# WASM module
if [ -f "$PROJECT_ROOT/GaiaFusion/Resources/gaiafusion_substrate.wasm" ]; then
    cp "$PROJECT_ROOT/GaiaFusion/Resources/gaiafusion_substrate.wasm" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ gaiafusion_substrate.wasm"
else
    echo "   ⚠️  gaiafusion_substrate.wasm not found"
fi

# WASM bindgen
if [ -f "$PROJECT_ROOT/GaiaFusion/Resources/gaiafusion_substrate_bindgen.js" ]; then
    cp "$PROJECT_ROOT/GaiaFusion/Resources/gaiafusion_substrate_bindgen.js" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ gaiafusion_substrate_bindgen.js"
fi

# Fusion sidecar cell config
if [ -d "$PROJECT_ROOT/GaiaFusion/Resources/fusion-sidecar-cell" ]; then
    cp -R "$PROJECT_ROOT/GaiaFusion/Resources/fusion-sidecar-cell" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ fusion-sidecar-cell/"
fi

# Native fusion spec
if [ -d "$PROJECT_ROOT/GaiaFusion/Resources/spec/native_fusion" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/spec"
    cp -R "$PROJECT_ROOT/GaiaFusion/Resources/spec/native_fusion" "$APP_BUNDLE/Contents/Resources/spec/"
    echo "   ✅ spec/native_fusion/"
fi

# Branding
if [ -d "$PROJECT_ROOT/GaiaFusion/Resources/Branding" ]; then
    cp -R "$PROJECT_ROOT/GaiaFusion/Resources/Branding" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ Branding/"
fi

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.fortressai.gaiafusion</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 FortressAI Research Institute. USPTO 19/460,960.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
EOF

# Verify bundle
echo ""
echo "✅ Bundle created: $APP_BUNDLE"
echo "📊 Bundle size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
echo "📋 Bundle contents:"
find "$APP_BUNDLE" -type f | head -20
echo ""

# Test if bundle is valid
if [ -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]; then
    echo "✅ Binary is executable"
else
    echo "❌ ERROR: Binary is not executable"
    exit 1
fi

if [ -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    echo "✅ Info.plist exists"
    
    # Validate plist
    if plutil -lint "$APP_BUNDLE/Contents/Info.plist" > /dev/null 2>&1; then
        echo "✅ Info.plist is valid"
    else
        echo "⚠️  Info.plist may have issues"
    fi
else
    echo "❌ ERROR: Info.plist missing"
    exit 1
fi

echo ""
echo "🎉 ${APP_NAME}.app bundle ready!"
echo ""
echo "To test:"
echo "  open $APP_BUNDLE"
echo ""
echo "To create DMG:"
echo "  bash scripts/build_dmg.sh"
echo ""
