#!/usr/bin/env python3
"""
Generate Founder's Ethereum Wallet with Cryptographically Secure Private Key

This script generates a new Ethereum wallet for the GaiaFTCL founder with:
- Cryptographically secure random private key generation
- Immediate display of wallet address and private key
- Instructions for storing in macOS Keychain
- Validation of key generation

SECURITY: This script displays the private key ONCE. Store it immediately in keychain.
"""

import secrets
import sys
from eth_account import Account
from eth_utils import to_checksum_address

def generate_secure_wallet():
    """Generate cryptographically secure Ethereum wallet"""
    
    print("=" * 80)
    print("GAIAFTCL FOUNDER WALLET GENERATION")
    print("=" * 80)
    print()
    
    # Generate 32 bytes (256 bits) of cryptographically secure random data
    print("[1/4] Generating cryptographically secure private key...")
    private_key_bytes = secrets.token_bytes(32)
    private_key = "0x" + private_key_bytes.hex()
    
    # Create account from private key
    print("[2/4] Deriving Ethereum address from private key...")
    account = Account.from_key(private_key)
    wallet_address = to_checksum_address(account.address)
    
    # Validate the wallet
    print("[3/4] Validating wallet generation...")
    try:
        # Test signing a message to ensure key works
        test_message = "GaiaFTCL Founder Wallet Validation"
        from eth_account.messages import encode_defunct
        message_hash = encode_defunct(text=test_message)
        signature = account.sign_message(message_hash)
        
        # Verify signature
        recovered_address = Account.recover_message(message_hash, signature=signature.signature)
        assert recovered_address.lower() == wallet_address.lower(), "Signature verification failed"
        
        print("✓ Wallet validation successful")
    except Exception as e:
        print(f"✗ Wallet validation FAILED: {e}")
        sys.exit(1)
    
    # Display results
    print("[4/4] Wallet generation complete")
    print()
    print("=" * 80)
    print("FOUNDER WALLET DETAILS")
    print("=" * 80)
    print()
    print(f"Wallet Address: {wallet_address}")
    print()
    print(f"Private Key: {private_key}")
    print()
    print("=" * 80)
    print("⚠️  CRITICAL SECURITY INSTRUCTIONS")
    print("=" * 80)
    print()
    print("1. COPY the private key above to your clipboard")
    print("2. RUN the following command to store in macOS Keychain:")
    print()
    print(f'   security add-generic-password \\')
    print(f'     -a "gaiaftcl_founder" \\')
    print(f'     -s "eth_private_key" \\')
    print(f'     -w "{private_key}" \\')
    print(f'     -T ""')
    print()
    print("3. VERIFY keychain storage:")
    print()
    print('   security find-generic-password -a "gaiaftcl_founder" -s "eth_private_key" -w')
    print()
    print("4. CLOSE this terminal window after storing (clears screen buffer)")
    print()
    print("5. RUN backup script:")
    print()
    print("   ./scripts/store_key_in_keychain.sh")
    print()
    print("=" * 80)
    print("⚠️  NEVER commit this private key to git or store in plaintext files")
    print("=" * 80)
    print()
    
    return {
        "address": wallet_address,
        "private_key": private_key
    }

if __name__ == "__main__":
    try:
        wallet = generate_secure_wallet()
        
        # Write address to a safe file for migration script
        with open("/tmp/gaiaftcl_new_founder_address.txt", "w") as f:
            f.write(wallet["address"])
        
        print(f"New wallet address saved to: /tmp/gaiaftcl_new_founder_address.txt")
        print()
        
    except Exception as e:
        print(f"ERROR: Wallet generation failed: {e}")
        sys.exit(1)
