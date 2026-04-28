#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
GAIA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACADE_DIR="$GAIA_ROOT/services/gaiaftcl_sovereign_facade"
BUILD_DIR="$FACADE_DIR/build/gaiaftcl_facade"
DIST_DIR="$GAIA_ROOT/dist"
APP_NAME="GaiaFTCL.app"
DMG_NAME="GaiaFTCL-${VERSION}.dmg"

echo "🔨 Building GaiaFTCL Sovereign Facade"
echo "Version: $VERSION"
echo ""

# Clean previous builds
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# Build Swift app
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Compiling Swift sources..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$FACADE_DIR"

# Create Xcode project structure
mkdir -p "$BUILD_DIR/$APP_NAME/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME/Contents/Resources"

# Compile Swift sources
swiftc \
    -o "$BUILD_DIR/$APP_NAME/Contents/MacOS/GaiaFTCL" \
    -framework AppKit \
    -framework Foundation \
    -framework LocalAuthentication \
    -framework Security \
    src/mount_and_events.swift \
    src/gaiaftcl_app.swift \
    src/s4_ingestor.swift \
    src/identity_mooring.swift \
    src/projection_engine.swift \
    src/color_state_projection.swift \
    src/state_dashboard.swift \
    src/entry_point.swift \
    || {
    echo "❌ Swift compilation failed"
    echo "Note: This requires Xcode and Swift toolchain on macOS"
    exit 1
  }

# Create Info.plist
cat > "$BUILD_DIR/$APP_NAME/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>GaiaFTCL</string>
    <key>CFBundleDisplayName</key>
    <string>GaiaFTCL Sovereign Facade</string>
    <key>CFBundleIdentifier</key>
    <string>com.gaiaftcl.sovereign-facade</string>
    <key>CFBundleVersion</key>
    <string>VERSION_PLACEHOLDER</string>
    <key>CFBundleShortVersionString</key>
    <string>VERSION_PLACEHOLDER</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>GFTC</string>
    <key>CFBundleExecutable</key>
    <string>GaiaFTCL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

# Replace version placeholder
sed -i '' "s/VERSION_PLACEHOLDER/$VERSION/g" "$BUILD_DIR/$APP_NAME/Contents/Info.plist"

# Create app icon (Light Blue themed)
echo "🎨 Creating app icon..."
# TODO: Create proper .icns file with Light Blue theme

# Copy resources (cwd is services/gaiaftcl_sovereign_facade)
cp -r src "$BUILD_DIR/$APP_NAME/Contents/Resources/"

cd "$GAIA_ROOT"

echo "✅ App bundle created"
echo ""

# Create DMG
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Creating DMG..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create temporary DMG directory
DMG_TEMP="$BUILD_DIR/dmg_temp"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -r "$BUILD_DIR/$APP_NAME" "$DMG_TEMP/"

# Mac cell membrane (probationary → measured): bin + spring seeds for /Volumes/GaiaFTCL
MAC_MOUNT_SRC="$GAIA_ROOT/deploy/mac_cell_mount"
if [ -d "$MAC_MOUNT_SRC" ]; then
  mkdir -p "$DMG_TEMP/bin" "$DMG_TEMP/spring" "$DMG_TEMP/nats"
  cp "$MAC_MOUNT_SRC/bin/"* "$DMG_TEMP/bin/"
  cp "$MAC_MOUNT_SRC/spring/"* "$DMG_TEMP/spring/"
  cp -R "$MAC_MOUNT_SRC/nats/"* "$DMG_TEMP/nats/" 2>/dev/null || true
  cp "$MAC_MOUNT_SRC/README_MEMBRANE.md" "$DMG_TEMP/README_MEMBRANE.md"
  if [ -f "$MAC_MOUNT_SRC/FUSION_DM_VIRTUAL_AND_PRODUCTION.md" ]; then
    cp "$MAC_MOUNT_SRC/FUSION_DM_VIRTUAL_AND_PRODUCTION.md" "$DMG_TEMP/FUSION_DM_VIRTUAL_AND_PRODUCTION.md"
  fi
  chmod +x "$DMG_TEMP/bin/"*
  echo "✅ Mac cell mount bundle copied to DMG (bin/, spring/, nats/, README_MEMBRANE.md, fusion user flow doc)"
else
  echo "⚠️  deploy/mac_cell_mount missing — DMG without membrane scripts"
fi

# Fusion Mesh — M⁸ benchmark surfaces + MCP bridges (S4 manifests; bridges REFUSE until configured)
FUSION_MESH="$GAIA_ROOT/deploy/fusion_mesh/config/benchmarks"
if [ -d "$FUSION_MESH" ]; then
  mkdir -p "$DMG_TEMP/config/benchmarks"
  cp "$FUSION_MESH"/*.json "$DMG_TEMP/config/benchmarks/"
  mkdir -p "$DMG_TEMP/deploy/fusion_mesh/config/benchmarks"
  cp "$FUSION_MESH"/*.json "$DMG_TEMP/deploy/fusion_mesh/config/benchmarks/"
  echo "✅ Fusion Mesh benchmarks copied to DMG (config/benchmarks + deploy/fusion_mesh/config/benchmarks)"
else
  echo "⚠️  deploy/fusion_mesh/config/benchmarks missing"
fi

# S4 fusion projection + Turbo IDE scripts (long-run cell loop, control matrix, frame lib)
mkdir -p "$DMG_TEMP/deploy/fusion_mesh"
for f in fusion_projection.json fusion_projection.example.json fusion_live_hardware.example.json fusion_virtual_systems_catalog_s4.json FUSION_PLANT_MOORING_AND_MESH_PAYMENT.md FUSION_DMG_LONG_RUN_OPERATOR.md FUSION_OPERATOR_SURFACE.md; do
  if [ -f "$GAIA_ROOT/deploy/fusion_mesh/$f" ]; then
    cp "$GAIA_ROOT/deploy/fusion_mesh/$f" "$DMG_TEMP/deploy/fusion_mesh/"
  fi
done
mkdir -p "$DMG_TEMP/scripts/lib"
for lib in turbo_frames.sh turbo_keys.sh turbo_paths.sh fusion_mooring.sh; do
  [ -f "$GAIA_ROOT/scripts/lib/$lib" ] && cp "$GAIA_ROOT/scripts/lib/$lib" "$DMG_TEMP/scripts/lib/"
done
for s in fusion_surface.sh test_fusion_cli.sh fusion_plant_forensic.sh feed_nstxu.sh feed_pcssp.sh nstxu_benchmark_feeder.sh verify_fusion_operator_surface.sh fusion_turbo_ide.sh fusion_cell_long_run_runner.sh fusion_cell_long_run_stop.sh best_control_test_ever.sh build_fusion_control_mac_app.sh test_fusion_mesh_mooring_stack.sh fusion_stack_launch.sh fusion_stack_supervise.sh; do
  if [ -f "$GAIA_ROOT/scripts/$s" ]; then
    cp "$GAIA_ROOT/scripts/$s" "$DMG_TEMP/scripts/"
    chmod +x "$DMG_TEMP/scripts/$s"
  fi
done
mkdir -p "$DMG_TEMP/deploy/fusion_cell"
if [ -f "$GAIA_ROOT/deploy/fusion_cell/config.example.json" ]; then
  cp "$GAIA_ROOT/deploy/fusion_cell/config.example.json" "$DMG_TEMP/deploy/fusion_cell/"
fi
echo "✅ Fusion Turbo IDE + projection staged under scripts/ and deploy/fusion_mesh/"

# Fusion Control (Rust + Metal): 2000-cycle validation + entropy tax receipt; bundle app + evidence
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚡ FusionControl — 2000-cycle DMG gate + €0.10/kW tax receipt"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -f "$GAIA_ROOT/scripts/fusion_control_dmg_gate.sh" ]]; then
  chmod +x "$GAIA_ROOT/scripts/fusion_control_dmg_gate.sh"
  bash "$GAIA_ROOT/scripts/fusion_control_dmg_gate.sh"
  if [[ -d "$GAIA_ROOT/services/fusion_control_mac/dist/FusionControl.app" ]]; then
    mkdir -p "$DMG_TEMP/evidence/fusion_control"
    cp -R "$GAIA_ROOT/services/fusion_control_mac/dist/FusionControl.app" "$DMG_TEMP/"
    [[ -f "$GAIA_ROOT/evidence/fusion_control/dmg_gate_2000_cycle_receipt.json" ]] && \
      cp "$GAIA_ROOT/evidence/fusion_control/dmg_gate_2000_cycle_receipt.json" "$DMG_TEMP/evidence/fusion_control/"
    [[ -f "$GAIA_ROOT/services/fusion_control_mac/docs/FUSION_ENTROPY_TAX_AND_VALIDATION.md" ]] && \
      cp "$GAIA_ROOT/services/fusion_control_mac/docs/FUSION_ENTROPY_TAX_AND_VALIDATION.md" "$DMG_TEMP/evidence/fusion_control/"
    echo "✅ FusionControl.app + fusion evidence copied to DMG staging"
  else
    echo "⚠️  FusionControl.app not present after gate run; continuing without FusionControl payload"
  fi
else
  echo "⚠️  fusion_control_dmg_gate.sh missing — skipping FusionControl payload"
fi

# FusionSidecarHost — Xcode + Virtualization.framework (see deploy/mac_cell_mount/FUSION_SIDECAR_HOST_APP.md)
if [[ "${FUSION_DMG_INCLUDE_SIDECAR_HOST:-1}" == "1" ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📦 FusionSidecarHost.app (xcodebuild Release)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  SIDE_PROJ="$GAIA_ROOT/macos/FusionSidecarHost/FusionSidecarHost.xcodeproj"
  # Avoid repo-local DerivedData (xattrs → codesign "resource fork" failures on some volumes).
  SIDE_DERIVED="${TMPDIR:-/tmp}/gaiaftcl_facade_FusionSidecarHost_derived_${USER}"
  if [[ -d "$SIDE_PROJ" ]] && command -v xcodebuild >/dev/null 2>&1; then
    rm -rf "$SIDE_DERIVED"
    mkdir -p "$SIDE_DERIVED"
    _HARCH="$(uname -m)"
    case "$_HARCH" in
      arm64) _XDEST="platform=macOS,arch=arm64" ;;
      x86_64) _XDEST="platform=macOS,arch=x86_64" ;;
      *) _XDEST="platform=macOS" ;;
    esac
    if (cd "$GAIA_ROOT" && xcodebuild -project "$SIDE_PROJ" -scheme FusionSidecarHost -configuration Release \
        -derivedDataPath "$SIDE_DERIVED" ONLY_ACTIVE_ARCH=YES ARCHS="$_HARCH" \
        build -destination "$_XDEST" -quiet); then
      SIDE_APP="$SIDE_DERIVED/Build/Products/Release/FusionSidecarHost.app"
      if [[ -d "$SIDE_APP" ]]; then
        cp -R "$SIDE_APP" "$DMG_TEMP/"
        echo "✅ FusionSidecarHost.app copied to DMG staging"
      else
        echo "⚠️  xcodebuild ok but missing $SIDE_APP — DMG without FusionSidecarHost"
      fi
    else
      echo "⚠️  FusionSidecarHost xcodebuild failed — DMG continues without sidecar host app"
    fi
  else
    echo "⚠️  FusionSidecarHost skipped (no $SIDE_PROJ or xcodebuild not in PATH)"
  fi
else
  echo "SKIP FusionSidecarHost on DMG (FUSION_DMG_INCLUDE_SIDECAR_HOST=0)"
fi

# Create Applications symlink (idempotent across repeated outer-cure rebuild cycles)
ln -sfn /Applications "$DMG_TEMP/Applications"

# Create README
cat > "$DMG_TEMP/README.txt" << 'README'
GaiaFTCL Sovereign Facade
=========================

Installation:
1. Drag GaiaFTCL.app to Applications folder
2. Launch GaiaFTCL from Applications
3. Grant permissions when prompted
4. Complete Identity Mooring setup
5. Read README_MEMBRANE.md — run bin/cell_onboard.sh then bin/gaia_mount (Discord-membrane probationary→measured)
6. Fusion virtual vs production — FUSION_DM_VIRTUAL_AND_PRODUCTION.md (Discord mesh moor; S⁴ UI: virtual systems with N cycles or run-until-stopped; production grey until mooring + licensing + bridge invoke)
7. FusionControl.app — Metal validation + entropy tax receipt (see evidence/fusion_control/FUSION_ENTROPY_TAX_AND_VALIDATION.md; dmg_gate_2000_cycle_receipt.json)
8. FusionSidecarHost.app — Xcode + Virtualization host for in-app Linux sidecar (see README_MEMBRANE.md / FUSION_SIDECAR_HOST_APP.md on full checkout; DMG includes app when xcodebuild succeeds during packaging)
9. Fusion Mesh — config/benchmarks/*.json (S4 surfaces: OSTI baseline, PCSSP floor, TORAX, SCDDS); bin/mcp_bridge_torax, bin/mcp_bridge_marte2 (REFUSE until MCP_* or fusion_projection.json bridges.invoke set); fusion_virtual_systems_catalog_s4.json
10. Fusion Turbo IDE — bin/gaiaftcl_turbo_ide (long-run cell loop, optional DMG build from full checkout via GAIA_ROOT); deploy/fusion_mesh/fusion_projection.json (S4 labels + bridge argv + payment_projection); bin/fusion_stack_launch.sh (local stack)
11. Fusion mesh mooring — bin/fusion_mesh_mooring_heartbeat.sh (NATS ≥1×/24h for paid tier); deploy/fusion_mesh/FUSION_PLANT_MOORING_AND_MESH_PAYMENT.md
12. Drop files into /Volumes/GaiaFTCL to project to mesh

Requirements:
- macOS 11.0 or later
- Internet connection
- Ethereum wallet

Support:
- Website: https://gaiaftcl.com
- Documentation: https://gaiaftcl.com/docs

---
Version: VERSION_PLACEHOLDER
Build Date: BUILD_DATE_PLACEHOLDER
README

sed -i '' "s/VERSION_PLACEHOLDER/$VERSION/g" "$DMG_TEMP/README.txt"
sed -i '' "s/BUILD_DATE_PLACEHOLDER/$(date -u +%Y-%m-%d)/g" "$DMG_TEMP/README.txt"

# Create DMG using hdiutil
hdiutil create \
    -volname "GaiaFTCL" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME"

echo "✅ DMG created: $DIST_DIR/$DMG_NAME"
echo ""

# C4 mount invariant + run_full_release_invariant.py: same payload, volume name GaiaFusion → /Volumes/GaiaFusion
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📀 GaiaFusion.dmg (volname GaiaFusion — mount gate)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
hdiutil create \
    -volname "GaiaFusion" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DIST_DIR/GaiaFusion.dmg"
echo "✅ DMG created: $DIST_DIR/GaiaFusion.dmg"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 hdiutil verify (DMG integrity)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
hdiutil verify "$DIST_DIR/$DMG_NAME"
hdiutil verify "$DIST_DIR/GaiaFusion.dmg"
echo "✅ hdiutil verify OK"
echo ""

# Generate checksum
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Generating checksum..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

shasum -a 256 "$DIST_DIR/$DMG_NAME" > "$DIST_DIR/$DMG_NAME.sha256"
CHECKSUM=$(cat "$DIST_DIR/$DMG_NAME.sha256" | awk '{print $1}')
shasum -a 256 "$DIST_DIR/GaiaFusion.dmg" > "$DIST_DIR/GaiaFusion.dmg.sha256"
echo "✅ Checksum GaiaFusion: $(awk '{print $1}' "$DIST_DIR/GaiaFusion.dmg.sha256")"

echo "✅ Checksum: $CHECKSUM"
echo ""

# Sign DMG (if Developer ID available)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Signing DMG..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --sign "$DEVELOPER_ID" --timestamp "$DIST_DIR/$DMG_NAME"
    codesign --sign "$DEVELOPER_ID" --timestamp "$DIST_DIR/GaiaFusion.dmg"
    echo "✅ DMG signed with Developer ID"
else
    echo "⚠️  No DEVELOPER_ID set - DMG not signed"
    echo "   Set DEVELOPER_ID environment variable to sign"
fi

echo ""

# Create version manifest
cat > "$DIST_DIR/version.json" << VERSION
{
  "version": "$VERSION",
  "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dmg_name": "$DMG_NAME",
  "checksum": "$CHECKSUM",
  "size": $(stat -f%z "$DIST_DIR/$DMG_NAME"),
  "required_os": "macOS 11.0+",
  "download_url": "https://gaiaftcl.com/downloads/$DMG_NAME"
}
VERSION

echo "✅ Version manifest created"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ BUILD COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "DMG: $DIST_DIR/$DMG_NAME"
echo "DMG (GaiaFusion): $DIST_DIR/GaiaFusion.dmg"
echo "Size: $(du -h "$DIST_DIR/$DMG_NAME" | awk '{print $1}')"
echo "Checksum: $CHECKSUM"
echo "Version: $VERSION"
echo ""
echo "Mesh deploy (nine cells): bash scripts/deploy_dmg_to_mesh.sh"
