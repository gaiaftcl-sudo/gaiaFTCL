#!/usr/bin/env bash
#
# Store Founder's Private Key in macOS Keychain
#
# This script:
# 1. Stores the private key in macOS Keychain (encrypted by OS)
# 2. Creates encrypted GPG backup
# 3. Generates QR code for cold storage
# 4. Verifies keychain storage
#
# SECURITY: Keychain is encrypted by macOS, requires Mac password to access

set -euo pipefail

PRIVATE_KEY_FILE="/tmp/gaiaftcl_new_founder_address.txt"
BACKUP_DIR="$HOME/.gaiaftcl_secure"

echo "================================================================================"
echo "GAIAFTCL FOUNDER WALLET - KEYCHAIN STORAGE"
echo "================================================================================"
echo ""

# Check if private key is in environment or needs manual input
if [ -z "${GAIAFTCL_FOUNDER_PRIVATE_KEY:-}" ]; then
    echo "⚠️  Private key not found in environment variable"
    echo ""
    echo "Please enter the private key (it will not be echoed):"
    read -s PRIVATE_KEY
    echo ""
else
    PRIVATE_KEY="$GAIAFTCL_FOUNDER_PRIVATE_KEY"
    echo "✓ Found private key in environment variable"
fi

# Validate private key format
if [[ ! "$PRIVATE_KEY" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
    echo "✗ Invalid private key format"
    echo "   Expected: 0x followed by 64 hexadecimal characters"
    exit 1
fi

echo "✓ Private key format validated"
echo ""

# Step 1: Store in macOS Keychain
echo "[1/4] Storing private key in macOS Keychain..."
security add-generic-password \
    -a "gaiaftcl_founder" \
    -s "eth_private_key" \
    -w "$PRIVATE_KEY" \
    -T "" \
    -U 2>/dev/null || {
    # If key already exists, update it
    security delete-generic-password -a "gaiaftcl_founder" -s "eth_private_key" 2>/dev/null || true
    security add-generic-password \
        -a "gaiaftcl_founder" \
        -s "eth_private_key" \
        -w "$PRIVATE_KEY" \
        -T "" \
        -U
}
echo "✓ Private key stored in macOS Keychain"
echo ""

# Step 2: Verify keychain storage
echo "[2/4] Verifying keychain storage..."
RETRIEVED_KEY=$(security find-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w 2>/dev/null || echo "")
if [ "$RETRIEVED_KEY" = "$PRIVATE_KEY" ]; then
    echo "✓ Keychain storage verified successfully"
else
    echo "✗ Keychain verification FAILED"
    exit 1
fi
echo ""

# Step 3: Create encrypted backup directory
echo "[3/4] Creating encrypted backup..."
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Create backup with GPG encryption
BACKUP_FILE="$BACKUP_DIR/founder_wallet_backup_$(date +%Y%m%d_%H%M%S).gpg"
echo "$PRIVATE_KEY" | gpg --symmetric --armor --cipher-algo AES256 --output "$BACKUP_FILE" 2>/dev/null || {
    echo "⚠️  GPG not available or not configured"
    echo "   Skipping encrypted backup (you can create it manually later)"
    BACKUP_FILE=""
}

if [ -n "$BACKUP_FILE" ]; then
    echo "✓ Encrypted backup created: $BACKUP_FILE"
    echo "   To decrypt: gpg --decrypt $BACKUP_FILE"
else
    echo "⚠️  No encrypted backup created"
fi
echo ""

# Step 4: Generate QR code (if qrencode is available)
echo "[4/4] Generating QR code for cold storage..."
if command -v qrencode &> /dev/null; then
    QR_FILE="$BACKUP_DIR/founder_wallet_qr_$(date +%Y%m%d_%H%M%S).png"
    echo "$PRIVATE_KEY" | qrencode -o "$QR_FILE" -s 10
    echo "✓ QR code generated: $QR_FILE"
    echo "   Print this for cold storage (then delete the file)"
else
    echo "⚠️  qrencode not installed, skipping QR code generation"
    echo "   Install with: brew install qrencode"
fi
echo ""

echo "================================================================================"
echo "KEYCHAIN STORAGE COMPLETE"
echo "================================================================================"
echo ""
echo "Private key is now stored in:"
echo "  1. macOS Keychain (encrypted by OS)"
if [ -n "$BACKUP_FILE" ]; then
    echo "  2. Encrypted GPG backup: $BACKUP_FILE"
fi
echo ""
echo "To retrieve the private key:"
echo '  security find-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w'
echo ""
echo "To use in scripts:"
echo '  PRIVATE_KEY=$(security find-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w)'
echo ""
echo "================================================================================"
echo "⚠️  SECURITY REMINDERS"
echo "================================================================================"
echo ""
echo "1. NEVER commit the private key to git"
echo "2. NEVER store in plaintext files (except encrypted backups)"
echo "3. BACKUP the encrypted GPG file to 1Password/LastPass"
echo "4. TEST recovery process before deleting any backups"
echo "5. CLEAR terminal history: history -c"
echo ""
echo "================================================================================"

# Clear the private key from memory
unset PRIVATE_KEY
unset RETRIEVED_KEY
unset GAIAFTCL_FOUNDER_PRIVATE_KEY
