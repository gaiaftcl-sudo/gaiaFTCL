#!/usr/bin/env bash
# GATE3: nats pub sign_request — compact payload MAX_PAYLOAD 4096.
#
# Test Wallet Signature Flow
#
# This script tests the end-to-end signature generation and verification:
# 1. Generates a test message
# 2. Signs it using the founder's private key from keychain
# 3. Verifies the signature
# 4. Tests the wallet_signer service (if running)

set -euo pipefail

WALLET_ADDRESS="0x91f6e41B4425326e42590191c50Db819C587D866"
TEST_DISCORD_ID="1487798260339966023"

echo "================================================================================"
echo "WALLET SIGNATURE FLOW TEST"
echo "================================================================================"
echo ""

# Test 1: Direct keychain access
echo "[Test 1/3] Testing direct keychain access..."
PRIVATE_KEY=$(security find-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w 2>/dev/null || echo "")

if [ -z "$PRIVATE_KEY" ]; then
    echo "✗ FAILED: Private key not found in keychain"
    echo "   Run: ./scripts/store_key_in_keychain.sh"
    exit 1
fi

echo "✓ Retrieved private key from keychain"
echo ""

# Test 2: Python signature generation
echo "[Test 2/3] Testing Python signature generation..."
python3 << ENDPYTHON
from eth_account import Account
from eth_account.messages import encode_defunct
import sys

private_key = "$PRIVATE_KEY"
wallet_address = "$WALLET_ADDRESS"
test_message = "GaiaFTCL Authentication\nTimestamp: 1234567890\nMessage: inception:$TEST_DISCORD_ID"

try:
    # Create account
    account = Account.from_key(private_key)
    
    # Verify address
    if account.address.lower() != wallet_address.lower():
        print(f"✗ FAILED: Address mismatch")
        print(f"   Expected: {wallet_address}")
        print(f"   Got: {account.address}")
        sys.exit(1)
    
    # Sign message
    message_hash = encode_defunct(text=test_message)
    signed_message = account.sign_message(message_hash)
    signature = signed_message.signature.hex()
    
    # Verify signature
    recovered_address = Account.recover_message(message_hash, signature=signed_message.signature)
    
    if recovered_address.lower() != wallet_address.lower():
        print(f"✗ FAILED: Signature verification failed")
        sys.exit(1)
    
    print(f"✓ Signature generated and verified")
    print(f"  Message: {test_message[:50]}...")
    print(f"  Signature: {signature[:20]}...{signature[-20:]}")
    print(f"  Recovered address: {recovered_address}")
    
except Exception as e:
    print(f"✗ FAILED: {e}")
    sys.exit(1)
ENDPYTHON

if [ $? -ne 0 ]; then
    exit 1
fi
echo ""

# Test 3: NATS integration (if wallet_signer is running)
echo "[Test 3/3] Testing NATS integration..."
if command -v nats &> /dev/null; then
    echo "  Publishing test signing request to NATS..."
    nats pub gaiaftcl.wallet.sign_request \
        "{\"request_id\":\"test-$(date +%s)\",\"discord_id\":\"$TEST_DISCORD_ID\",\"message\":\"inception:$TEST_DISCORD_ID\"}" \
        2>/dev/null && echo "  ✓ Published signing request" || echo "  ⚠️  NATS not available or wallet_signer not running"
else
    echo "  ⚠️  NATS CLI not installed, skipping NATS test"
    echo "     Install with: brew install nats-io/nats-tools/nats"
fi
echo ""

echo "================================================================================"
echo "TEST RESULTS"
echo "================================================================================"
echo ""
echo "✓ Keychain access: PASSED"
echo "✓ Signature generation: PASSED"
echo "✓ Signature verification: PASSED"
echo ""
echo "Wallet address: $WALLET_ADDRESS"
echo "Test Discord ID: $TEST_DISCORD_ID"
echo ""
echo "Next steps:"
echo "  1. Start wallet_signer: python3 services/wallet_signer/main.py"
echo "  2. Execute Discord /moor command"
echo "  3. Verify in ArangoDB: discord_wallet_entanglement collection"
echo ""
echo "================================================================================"
