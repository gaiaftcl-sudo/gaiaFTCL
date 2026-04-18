#!/usr/bin/env bash
set -euo pipefail

echo "=== IQ: Mac Cell Hardware Lock ==="

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
RECEIPT_DIR="evidence/iq"
mkdir -p "$RECEIPT_DIR"
RECEIPT_FILE="$RECEIPT_DIR/mac_cell_identity_${TIMESTAMP}.json"

STATE="CALORIE"
REASON=""

MODE="--fleet-member"
if [ "${1:-}" == "--standalone" ]; then
    MODE="--standalone"
fi

# --- 0. Temporal & Network Lock ---
echo "Checking Temporal Lock (sntp)..."
OFFSET_MS=$(sntp -d pool.ntp.org 2>/dev/null | awk '/selected:/,/\}/' | grep 'offset:' | grep -oE '\([0-9.-]+\)' | tr -d '()' | awk '{print $1 * 1000}' | cut -d. -f1 || echo "9999")
STRATUM=$(sntp -d pool.ntp.org 2>/dev/null | awk '/selected:/,/\}/' | grep 'stratum:' | grep -oE '\([0-9]+\)' | tr -d '()' || echo "9")

# Remove negative signs for comparison
ABS_OFFSET=${OFFSET_MS#-}

if [ "$ABS_OFFSET" -gt 100 ]; then
    STATE="REFUSED"
    REASON="Clock offset ${OFFSET_MS}ms > 100ms"
fi

if [ "$STRATUM" -gt 3 ]; then
    STATE="REFUSED"
    REASON="NTP stratum ${STRATUM} > 3"
fi

if [ "$MODE" == "--fleet-member" ]; then
    echo "Checking NATS JetStream..."
    # Simple check if NATS is listening on 4222
    if ! nc -z localhost 4222 2>/dev/null; then
        STATE="REFUSED"
        REASON="NATS JetStream not running on localhost:4222"
    fi
else
    echo "Running in standalone mode (skipping NATS check)."
fi

# --- 1. Anti-VM Signals ---
echo "Checking Anti-VM Signals..."

ARM64=$(sysctl -n hw.optional.arm64 2>/dev/null || echo "0")
if [ "$ARM64" != "1" ]; then
    STATE="REFUSED"
    REASON="Not Apple Silicon (hw.optional.arm64 != 1)"
fi

BRAND=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
if [[ "$BRAND" != *Apple\ M* ]]; then
    STATE="REFUSED"
    REASON="Not Apple Silicon (machdep.cpu.brand_string: $BRAND)"
fi

SMC=$(ioreg -c AppleSMC 2>/dev/null | grep AppleSMC || echo "")
if [ -z "$SMC" ]; then
    STATE="REFUSED"
    REASON="AppleSMC not found (VM detected)"
fi

SEP=$(ioreg -c AppleSEPManager 2>/dev/null | grep AppleSEPManager || echo "")
if [ -z "$SEP" ]; then
    STATE="REFUSED"
    REASON="AppleSEPManager not found (VM detected)"
fi

# Secure Boot check (requires sudo, assuming NOPASSWD in sudoers)
SECURE_BOOT=$(sudo bputil -d 2>/dev/null | grep "Secure Boot" || echo "Unknown")
# We don't necessarily fail on this, but we log it.

# --- 2. Hardware Identity ---
echo "Ripping Hardware Identity..."

SOC=$(ioreg -l -p IOService 2>/dev/null | grep "chip-id" | awk '{print $4}' | head -1 || echo "Unknown")
MEM=$(sysctl -n hw.memsize 2>/dev/null || echo "Unknown")
SERIAL=$(ioreg -l -p IOService 2>/dev/null | grep IOPlatformSerialNumber | awk '{print $4}' | tr -d '"' | head -1 || echo "Unknown")
UUID=$(ioreg -arc IOPlatformExpertDevice -k IOPlatformUUID 2>/dev/null | grep IOPlatformUUID | awk '{print $4}' | tr -d '"' | head -1 || echo "Unknown")

# --- 3. Toolchain Verification ---
echo "Verifying Toolchain..."

SWIFT_VER=$(swift --version | head -1 | grep -oE 'version [0-9]+\.[0-9]+' | awk '{print $2}' || echo "0.0")
SDK_VER=$(xcrun -sdk macosx --show-sdk-version 2>/dev/null || echo "0.0")
CLANG_VER=$(clang --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
XCSEL=$(xcode-select -p 2>/dev/null || echo "Unknown")

EXPECTED_SWIFT_MAJOR="6"
EXPECTED_SDK_MIN="14"

SWIFT_MAJOR=${SWIFT_VER%%.*}
SDK_MAJOR=${SDK_VER%%.*}

if [ "$SWIFT_MAJOR" -lt "$EXPECTED_SWIFT_MAJOR" ]; then
    STATE="REFUSED"
    REASON="Swift version too old ($SWIFT_VER)"
fi

if [ "$SDK_MAJOR" -lt "$EXPECTED_SDK_MIN" ]; then
    STATE="REFUSED"
    REASON="macOS SDK version too old ($SDK_VER)"
fi

# --- 4. Cryptographic Hash & Timestamp ---
echo "Generating Receipt..."

# Create the JSON payload
cat > "$RECEIPT_FILE.tmp" <<EOF
{
  "receipt_id": "GFTCL-IQ-HWLOCK-${TIMESTAMP}",
  "terminal_state": "$STATE",
  "reason": "$REASON",
  "hardware": {
    "chip_brand": "$BRAND",
    "soc_id": "$SOC",
    "memory_bytes": "$MEM",
    "serial_number": "$SERIAL",
    "platform_uuid": "$UUID",
    "secure_boot": "$SECURE_BOOT"
  },
  "toolchain": {
    "xcode_select_path": "$XCSEL",
    "swift_version": "$SWIFT_VER",
    "clang_version": "$CLANG_VER",
    "macos_sdk_version": "$SDK_VER"
  },
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Hash the payload
PAYLOAD_HASH=$(shasum -a 256 "$RECEIPT_FILE.tmp" | awk '{print $1}')

# Add the hash to the final JSON
jq --arg hash "$PAYLOAD_HASH" '. + {evidence_hash: $hash}' "$RECEIPT_FILE.tmp" > "$RECEIPT_FILE"
rm "$RECEIPT_FILE.tmp"

# Optional: RFC 3161 TSA Timestamping (using FreeTSA as an example)
# In a real production environment, you would use a robust TSA and save the .tsr file.
# curl -H "Content-Type: application/timestamp-query" --data-binary @query.tsq https://freetsa.org/tsr > evidence/iq/mac_cell_identity_${TIMESTAMP}.tsr

echo "IQ Receipt written to $RECEIPT_FILE"
echo "Evidence Hash: $PAYLOAD_HASH"
echo "State: $STATE"

if [ "$STATE" = "REFUSED" ]; then
    echo "IQ FAILED: $REASON"
    exit 10
fi

# Export the hash for the next stage
echo "$PAYLOAD_HASH" > "$RECEIPT_DIR/latest_iq_hash.txt"

echo "=== IQ Complete ==="
exit 0
