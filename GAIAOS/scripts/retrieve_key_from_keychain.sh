#!/usr/bin/env bash
#
# Retrieve Founder's Private Key from macOS Keychain
#
# Usage:
#   PRIVATE_KEY=$(./scripts/retrieve_key_from_keychain.sh)
#   echo "Key: $PRIVATE_KEY"

set -euo pipefail

# Retrieve private key from keychain
PRIVATE_KEY=$(security find-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w 2>/dev/null || echo "")

if [ -z "$PRIVATE_KEY" ]; then
    echo "ERROR: Private key not found in keychain" >&2
    echo "Run: ./scripts/store_key_in_keychain.sh" >&2
    exit 1
fi

# Validate format
if [[ ! "$PRIVATE_KEY" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
    echo "ERROR: Invalid private key format in keychain" >&2
    exit 1
fi

# Output the key
echo "$PRIVATE_KEY"
