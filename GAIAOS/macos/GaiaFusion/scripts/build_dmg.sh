#!/bin/bash
# GaiaFusion DMG Builder
# Creates distributable disk image for macOS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="GaiaFusion"
APP_BUNDLE="$PROJECT_ROOT/${APP_NAME}.app"
VERSION="1.0.0-beta.1"
DMG_NAME="${APP_NAME}-${VERSION}"
DMG_PATH="$PROJECT_ROOT/${DMG_NAME}.dmg"
TEMP_DMG="$PROJECT_ROOT/tmp_${DMG_NAME}.dmg"

echo "💿 Building ${DMG_NAME}.dmg..."

# Check if .app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ ERROR: ${APP_NAME}.app not found"
    echo "   Run: bash scripts/build_app_bundle.sh"
    exit 1
fi

# Remove existing DMG
if [ -f "$DMG_PATH" ]; then
    echo "🧹 Removing existing DMG..."
    rm -f "$DMG_PATH"
fi

if [ -f "$TEMP_DMG" ]; then
    rm -f "$TEMP_DMG"
fi

# Create DMG
echo "📀 Creating disk image..."
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDRW "$TEMP_DMG"

# Mount and customize
echo "🎨 Customizing DMG..."
DEV_NAME=$(hdiutil attach "$TEMP_DMG" | grep "/Volumes/$APP_NAME" | awk '{print $1}')
MOUNT_POINT="/Volumes/$APP_NAME"

# Wait for mount
sleep 2

if [ -d "$MOUNT_POINT" ]; then
    # Create Applications symlink
    ln -s /Applications "$MOUNT_POINT/Applications"
    
    # Set custom icon if available
    if [ -f "$APP_BUNDLE/Contents/Resources/Branding/AppIcon.icns" ]; then
        cp "$APP_BUNDLE/Contents/Resources/Branding/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
        SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns"
    fi
    
    # Create README
    cat > "$MOUNT_POINT/README.txt" << EOF
GaiaFusion v${VERSION}
FortressAI Research Institute

CERN-Ready Fusion Control Interface
USPTO 19/460,960 - Quantum-Enhanced Graph Inference

INSTALLATION:
1. Drag GaiaFusion.app to Applications folder
2. Open from Applications
3. Grant necessary permissions when prompted

REQUIREMENTS:
- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3)
- 4GB RAM minimum

GAMP 5 COMPLIANCE:
- IQ/OQ/PQ documentation included in app bundle
- 21 CFR Part 11 compliant audit trail
- EU Annex 11 authorization controls

For support: research@fortressai.com

© 2026 FortressAI Research Institute
Norwich, Connecticut
EOF
    
    # Unmount
    hdiutil detach "$DEV_NAME"
    sleep 1
else
    echo "⚠️  Could not mount DMG for customization"
    hdiutil detach "$DEV_NAME" 2>/dev/null || true
fi

# Convert to compressed read-only
echo "🗜️  Compressing DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_PATH"

# Clean up
rm -f "$TEMP_DMG"

# Verify
if [ -f "$DMG_PATH" ]; then
    echo ""
    echo "✅ DMG created: $DMG_PATH"
    echo "📊 DMG size: $(du -sh "$DMG_PATH" | cut -f1)"
    
    # Test mount
    echo "🧪 Testing DMG..."
    TEST_MOUNT=$(hdiutil attach "$DMG_PATH" | grep "/Volumes/$APP_NAME" | awk '{print $1}')
    if [ -d "/Volumes/$APP_NAME" ]; then
        echo "✅ DMG mounts successfully"
        hdiutil detach "$TEST_MOUNT"
    else
        echo "⚠️  Could not verify DMG mount"
    fi
    
    echo ""
    echo "🎉 ${DMG_NAME}.dmg ready for distribution!"
    echo ""
    echo "To test:"
    echo "  open $DMG_PATH"
    echo ""
else
    echo "❌ ERROR: DMG creation failed"
    exit 1
fi
