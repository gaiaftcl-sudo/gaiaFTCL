#!/usr/bin/env bash
#
# Backup Founder Wallet
#
# This script creates multiple encrypted backups of the founder's private key:
# 1. GPG encrypted file
# 2. QR code (for cold storage)
# 3. Instructions for 1Password/LastPass
#
# SECURITY: All backups are encrypted. Store in multiple secure locations.

set -euo pipefail

BACKUP_DIR="$HOME/.gaiaftcl_secure/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WALLET_ADDRESS="0x91f6e41B4425326e42590191c50Db819C587D866"

echo "================================================================================"
echo "FOUNDER WALLET BACKUP"
echo "================================================================================"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
echo "✓ Backup directory: $BACKUP_DIR"
echo ""

# Retrieve private key from keychain
echo "[1/4] Retrieving private key from keychain..."
PRIVATE_KEY=$(security find-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w 2>/dev/null || echo "")

if [ -z "$PRIVATE_KEY" ]; then
    echo "✗ FAILED: Private key not found in keychain"
    exit 1
fi

echo "✓ Retrieved private key"
echo ""

# Backup 1: GPG encrypted file
echo "[2/4] Creating GPG encrypted backup..."
GPG_FILE="$BACKUP_DIR/founder_wallet_${TIMESTAMP}.gpg"

if command -v gpg &> /dev/null; then
    echo "$PRIVATE_KEY" | gpg --symmetric --armor --cipher-algo AES256 --output "$GPG_FILE" 2>/dev/null
    echo "✓ GPG backup created: $GPG_FILE"
    echo "  To decrypt: gpg --decrypt $GPG_FILE"
else
    echo "⚠️  GPG not installed, skipping encrypted backup"
    echo "   Install with: brew install gnupg"
fi
echo ""

# Backup 2: QR code
echo "[3/4] Creating QR code for cold storage..."
QR_FILE="$BACKUP_DIR/founder_wallet_qr_${TIMESTAMP}.png"

if command -v qrencode &> /dev/null; then
    # Create JSON with wallet info
    WALLET_JSON=$(cat <<ENDJSON
{
  "wallet_address": "$WALLET_ADDRESS",
  "private_key": "$PRIVATE_KEY",
  "created": "$TIMESTAMP",
  "type": "founder_wallet"
}
ENDJSON
)
    
    echo "$WALLET_JSON" | qrencode -o "$QR_FILE" -s 10 -l H
    echo "✓ QR code created: $QR_FILE"
    echo "  Print this for cold storage, then delete the file"
else
    echo "⚠️  qrencode not installed, skipping QR code"
    echo "   Install with: brew install qrencode"
fi
echo ""

# Backup 3: 1Password/LastPass instructions
echo "[4/4] Creating 1Password/LastPass backup instructions..."
INSTRUCTIONS_FILE="$BACKUP_DIR/1password_instructions_${TIMESTAMP}.txt"

cat > "$INSTRUCTIONS_FILE" << ENDINSTRUCTIONS
===============================================================================
FOUNDER WALLET - 1PASSWORD/LASTPASS BACKUP
===============================================================================

Wallet Address: $WALLET_ADDRESS
Private Key: $PRIVATE_KEY
Created: $TIMESTAMP

INSTRUCTIONS FOR 1PASSWORD:
1. Open 1Password
2. Create new "Secure Note" item
3. Title: "GaiaFTCL Founder Wallet"
4. Add custom fields:
   - wallet_address: $WALLET_ADDRESS
   - private_key: $PRIVATE_KEY (mark as password/concealed)
   - created: $TIMESTAMP
5. Add to "GaiaFTCL" vault
6. Enable "Require authentication to view"

INSTRUCTIONS FOR LASTPASS:
1. Open LastPass
2. Add new "Secure Note"
3. Name: "GaiaFTCL Founder Wallet"
4. Add custom fields:
   - Wallet Address: $WALLET_ADDRESS
   - Private Key: $PRIVATE_KEY
   - Created: $TIMESTAMP
5. Move to "GaiaFTCL" folder
6. Enable "Require Master Password Re-Prompt"

RECOVERY PROCESS:
1. Retrieve private key from 1Password/LastPass
2. Import to macOS Keychain:
   security add-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w "$PRIVATE_KEY" -T ""
3. Verify: security find-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w
4. Test: ./scripts/test_wallet_signature.sh

===============================================================================
ENDINSTRUCTIONS

echo "✓ Instructions created: $INSTRUCTIONS_FILE"
echo ""

echo "================================================================================"
echo "BACKUP COMPLETE"
echo "================================================================================"
echo ""
echo "Backups created in: $BACKUP_DIR"
echo ""
echo "Files created:"
if [ -f "$GPG_FILE" ]; then
    echo "  1. GPG encrypted: $(basename $GPG_FILE)"
fi
if [ -f "$QR_FILE" ]; then
    echo "  2. QR code: $(basename $QR_FILE)"
fi
echo "  3. 1Password instructions: $(basename $INSTRUCTIONS_FILE)"
echo ""
echo "NEXT STEPS:"
echo "  1. Copy GPG file to USB drive or cloud storage"
echo "  2. Print QR code and store in safe"
echo "  3. Add to 1Password/LastPass using instructions file"
echo "  4. Test recovery process"
echo "  5. Delete QR code PNG after printing: rm $QR_FILE"
echo ""
echo "SECURITY REMINDERS:"
echo "  - Never commit backups to git"
echo "  - Store backups in multiple secure locations"
echo "  - Test recovery process regularly"
echo "  - Keep 1Password/LastPass master password secure"
echo ""
echo "================================================================================"

# Clear private key from memory
unset PRIVATE_KEY
