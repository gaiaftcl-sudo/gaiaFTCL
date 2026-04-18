#!/usr/bin/env bash
set -euo pipefail

echo "=== PQ: Sovereign Package & Release Gate ==="

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
RECEIPT_DIR="evidence/pq"
mkdir -p "$RECEIPT_DIR"
RECEIPT_FILE="$RECEIPT_DIR/pq_package_gate_${TIMESTAMP}.json"

# Load parent hash
OQ_HASH_FILE="evidence/oq/latest_oq_hash.txt"
if [ ! -f "$OQ_HASH_FILE" ]; then
    echo "Error: Missing OQ hash. Run OQ phase first."
    exit 30
fi
PARENT_HASH=$(cat "$OQ_HASH_FILE")

STATE="CALORIE"
REASON=""

# --- 1. Build (Headless) ---
echo "Building App..."

APP_BUNDLE="services/fusion_control_mac/dist/FusionControl.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Running build script to generate app bundle..."
    ./scripts/build_fusion_control_mac_app.sh || { STATE="REFUSED"; REASON="Build failed"; }
fi

if [ "$STATE" = "REFUSED" ]; then
    echo "PQ FAILED: $REASON"
    exit 30
fi

# --- 2. Ad-Hoc Signing ---
echo "Ad-Hoc Signing the app bundle..."
# Clear extended attributes (resource forks, etc.) that block codesign
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || {
    STATE="REFUSED"
    REASON="Ad-Hoc codesign failed"
}

if [ "$STATE" = "REFUSED" ]; then
    echo "PQ FAILED: $REASON"
    exit 30
fi

# --- 3. DMG Packaging ---
echo "Packaging into DMG..."
DMG_FILE="/tmp/FusionControl_${TIMESTAMP}.dmg"
hdiutil create -volname "FusionControl" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_FILE" >/dev/null || {
    STATE="REFUSED"
    REASON="DMG creation failed"
}

if [ "$STATE" = "REFUSED" ]; then
    echo "PQ FAILED: $REASON"
    exit 30
fi

# --- 4. Cryptographic Hash & Timestamp ---
echo "Generating Receipt..."

DMG_HASH=$(shasum -a 256 "$DMG_FILE" | awk '{print $1}')

cat > "$RECEIPT_FILE.tmp" <<EOF
{
  "receipt_id": "GFTCL-PQ-PACKAGE-${TIMESTAMP}",
  "parent_hash": "$PARENT_HASH",
  "terminal_state": "$STATE",
  "reason": "$REASON",
  "packaging": {
    "dmg_path": "$DMG_FILE",
    "dmg_hash": "$DMG_HASH",
    "signing": "Ad-Hoc"
  },
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

PAYLOAD_HASH=$(shasum -a 256 "$RECEIPT_FILE.tmp" | awk '{print $1}')
jq --arg hash "$PAYLOAD_HASH" '. + {evidence_hash: $hash}' "$RECEIPT_FILE.tmp" > "$RECEIPT_FILE"
rm "$RECEIPT_FILE.tmp"

echo "PQ Receipt written to $RECEIPT_FILE"
echo "Evidence Hash: $PAYLOAD_HASH"
echo "State: $STATE"

echo "$PAYLOAD_HASH" > "$RECEIPT_DIR/latest_pq_hash.txt"

echo "=== PQ Complete ==="
exit 0
