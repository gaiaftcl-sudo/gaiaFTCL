# GAIAFTCL — IDENTITY BINDING PROTOCOL

**Version:** 1.0.0  
**Status:** CONSTITUTIONAL  
**Date:** 2026-01-20  
**Authority:** Founder

---

## ABSTRACT

This specification defines the **Web2-Web3 Hybrid Identity Gateway** for GaiaFTCL. External entities bind cryptographic wallet identities to email addresses, enabling:

1. **Verified Claims** — Prove authorship via signature
2. **Trust Scoring** — Reputation-based friction pricing
3. **QFOT Operations** — Wallet-bound treasury transactions
4. **External Contributor Onboarding** — Permissionless participation

---

## PART I: IDENTITY MODEL

### 1.1 The Dual-Handle Architecture

```
┌─────────────────────────────────────────────────────────────┐
│           GAIAFTCL IDENTITY BINDING                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   EMAIL (Web2 Handle)              WALLET (Web3 Handle)     │
│   ┌─────────────────┐              ┌─────────────────┐     │
│   │ alice@corp.com  │──── BIND ────│ 0x71C7...d897   │     │
│   └─────────────────┘              └─────────────────┘     │
│          │                                  │               │
│          ▼                                  ▼               │
│   Routing/Discovery              Cryptographic Proof        │
│   Human-readable                 Non-repudiable             │
│   Enterprise-compatible          Pseudonymous               │
│                                                             │
│   ┌─────────────────────────────────────────────────┐      │
│   │              DID DOCUMENT                        │      │
│   │  did:gaiaftcl:alice_at_corp_com                 │      │
│   │  ├── email: alice@corp.com                      │      │
│   │  ├── wallet: 0x71C7...d897                      │      │
│   │  ├── public_key: 0x04a1b2...                    │      │
│   │  ├── status: VERIFIED                           │      │
│   │  ├── entity_type: EXTERNAL_CONTRIBUTOR          │      │
│   │  └── trust_score: 85.0                          │      │
│   └─────────────────────────────────────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Entity Types

| Type | Description | Default Trust | QFOT Multiplier |
|------|-------------|---------------|-----------------|
| `INTERNAL_AGENT` | GaiaFTCL system entity | 100.0 | 0.0x (free) |
| `FOUNDER` | Founder accounts | 100.0 | 0.0x (free) |
| `VERIFIED_PARTNER` | Whitelisted organizations | 95.0 | 0.5x |
| `EXTERNAL_CONTRIBUTOR` | Bound external users | 50.0 | 1.0x |
| `ANONYMOUS` | Unbound email (no wallet) | 10.0 | 5.0x |
| `FLAGGED` | Known bad actor | 0.0 | 100.0x |
| `BANNED` | Permanently blocked | -1.0 | REJECTED |

### 1.3 Trust Score Calculation

```python
def calculate_trust_score(entity: dict, history: list) -> float:
    """
    Trust score is dynamic, based on:
    - Wallet binding status
    - Historical game participation
    - Claim accuracy rate
    - Community vouches
    - Time since binding
    """
    base_score = {
        "INTERNAL_AGENT": 100.0,
        "FOUNDER": 100.0,
        "VERIFIED_PARTNER": 95.0,
        "EXTERNAL_CONTRIBUTOR": 50.0,
        "ANONYMOUS": 10.0,
        "FLAGGED": 0.0,
        "BANNED": -1.0
    }.get(entity.get("entity_type"), 10.0)
    
    if base_score <= 0:
        return base_score
    
    # Positive factors
    claims_verified = sum(1 for h in history if h.get("verified"))
    games_completed = sum(1 for h in history if h.get("game_closed"))
    days_since_bind = (datetime.now() - entity.get("bound_at", datetime.now())).days
    
    # Negative factors
    claims_disputed = sum(1 for h in history if h.get("disputed"))
    games_failed = sum(1 for h in history if h.get("game_failed"))
    
    # Calculate adjustment
    positive = (claims_verified * 0.5) + (games_completed * 1.0) + min(days_since_bind * 0.1, 10)
    negative = (claims_disputed * 2.0) + (games_failed * 3.0)
    
    adjusted = base_score + positive - negative
    return max(0.0, min(100.0, adjusted))
```

---

## PART II: BINDING PROTOCOL

### 2.1 The IDENTITY_BIND Game Move

External entities initiate binding by sending an email with a cryptographic signature.

**Move Type:** `IDENTITY_BIND`  
**Game:** `FTCL-IDENTITY`

#### Email Format

```
From: alice@corp.com
To: identity@gaiaftcl.com
Subject: [FTCL-IDENTITY] IDENTITY_BIND: Wallet Binding Request

I, the holder of email alice@corp.com, hereby bind the following wallet
to my identity within the GaiaFTCL system:

WALLET: 0x71C765Abc123456789012345678901234567d897
CHAIN: ethereum-mainnet
TIMESTAMP: 2026-01-20T14:30:00Z

This binding is:
- VOLUNTARY and REVOCABLE
- BINDING for all FTCL game moves
- SUBJECT to GaiaFTCL constitutional rules

SIGNATURE: 0x4a8b2c3d...signature_hex...

---
To generate this signature, I signed the message:
"GAIAFTCL_BIND:alice@corp.com:0x71C765Abc123456789012345678901234567d897:2026-01-20T14:30:00Z"
with my wallet's private key.
```

### 2.2 Signature Generation (Client-Side)

Users generate signatures using standard Web3 tools:

#### Using MetaMask / Browser Wallet

```javascript
// JavaScript - Browser
async function generateBindingSignature(email, walletAddress) {
    const timestamp = new Date().toISOString();
    const message = `GAIAFTCL_BIND:${email}:${walletAddress}:${timestamp}`;
    
    // Request signature from MetaMask
    const signature = await ethereum.request({
        method: 'personal_sign',
        params: [message, walletAddress]
    });
    
    return {
        message,
        signature,
        timestamp,
        walletAddress
    };
}

// Usage
const binding = await generateBindingSignature(
    "alice@corp.com",
    "0x71C765Abc123456789012345678901234567d897"
);
console.log(`SIGNATURE: ${binding.signature}`);
```

#### Using ethers.js (Node.js)

```javascript
const { ethers } = require('ethers');

async function generateBindingSignature(privateKey, email, walletAddress) {
    const wallet = new ethers.Wallet(privateKey);
    const timestamp = new Date().toISOString();
    const message = `GAIAFTCL_BIND:${email}:${walletAddress}:${timestamp}`;
    
    const signature = await wallet.signMessage(message);
    
    return {
        message,
        signature,
        timestamp,
        walletAddress: wallet.address
    };
}
```

#### Using Python (web3.py)

```python
from web3 import Web3
from eth_account.messages import encode_defunct
from eth_account import Account
from datetime import datetime

def generate_binding_signature(private_key: str, email: str) -> dict:
    """Generate wallet binding signature."""
    account = Account.from_key(private_key)
    wallet_address = account.address
    timestamp = datetime.utcnow().isoformat() + "Z"
    
    message = f"GAIAFTCL_BIND:{email}:{wallet_address}:{timestamp}"
    message_encoded = encode_defunct(text=message)
    
    signed = account.sign_message(message_encoded)
    
    return {
        "email": email,
        "wallet_address": wallet_address,
        "timestamp": timestamp,
        "message": message,
        "signature": signed.signature.hex()
    }

# Usage
binding = generate_binding_signature(
    "0xYOUR_PRIVATE_KEY_HERE",
    "alice@corp.com"
)
print(f"WALLET: {binding['wallet_address']}")
print(f"TIMESTAMP: {binding['timestamp']}")
print(f"SIGNATURE: {binding['signature']}")
```

### 2.3 Signature Verification (Server-Side)

The Identity entity verifies binding requests:

```python
#!/usr/bin/env python3
"""
identity_verifier.py
Verifies wallet binding signatures
"""

from eth_account.messages import encode_defunct
from eth_account import Account
from datetime import datetime, timezone, timedelta
import re

def verify_binding_signature(
    email: str,
    wallet_address: str,
    timestamp: str,
    signature: str,
    max_age_minutes: int = 60
) -> dict:
    """
    Verify a wallet binding signature.
    
    Returns:
        {
            "valid": bool,
            "error": str or None,
            "recovered_address": str or None
        }
    """
    # 1. Validate timestamp freshness
    try:
        ts = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        age = now - ts
        
        if age > timedelta(minutes=max_age_minutes):
            return {"valid": False, "error": "Signature expired", "recovered_address": None}
        
        if age < timedelta(seconds=-60):  # Allow 1 min clock skew
            return {"valid": False, "error": "Timestamp in future", "recovered_address": None}
    except Exception as e:
        return {"valid": False, "error": f"Invalid timestamp: {e}", "recovered_address": None}
    
    # 2. Reconstruct the message
    message = f"GAIAFTCL_BIND:{email}:{wallet_address}:{timestamp}"
    message_encoded = encode_defunct(text=message)
    
    # 3. Recover signer address
    try:
        # Handle different signature formats
        if signature.startswith("0x"):
            sig_bytes = bytes.fromhex(signature[2:])
        else:
            sig_bytes = bytes.fromhex(signature)
        
        recovered = Account.recover_message(message_encoded, signature=sig_bytes)
    except Exception as e:
        return {"valid": False, "error": f"Signature recovery failed: {e}", "recovered_address": None}
    
    # 4. Compare addresses (case-insensitive)
    if recovered.lower() != wallet_address.lower():
        return {
            "valid": False,
            "error": f"Signer mismatch: expected {wallet_address}, got {recovered}",
            "recovered_address": recovered
        }
    
    return {
        "valid": True,
        "error": None,
        "recovered_address": recovered
    }


def parse_binding_email(body: str) -> dict:
    """
    Parse binding request from email body.
    
    Expected format:
        WALLET: 0x...
        CHAIN: ethereum-mainnet
        TIMESTAMP: 2026-01-20T14:30:00Z
        SIGNATURE: 0x...
    """
    patterns = {
        "wallet": r"WALLET:\s*(0x[a-fA-F0-9]{40})",
        "chain": r"CHAIN:\s*([a-z0-9-]+)",
        "timestamp": r"TIMESTAMP:\s*([0-9T:\-Z]+)",
        "signature": r"SIGNATURE:\s*(0x[a-fA-F0-9]+)"
    }
    
    result = {}
    for key, pattern in patterns.items():
        match = re.search(pattern, body, re.IGNORECASE)
        if match:
            result[key] = match.group(1)
    
    return result
```

### 2.4 ArangoDB Registry Schema

```python
# Collection: identities (extends wallets)

IDENTITY_DOCUMENT = {
    # Key
    "_key": "alice_at_corp_com",  # email normalized
    
    # Web2 Handle
    "email": "alice@corp.com",
    "email_verified": True,  # via DKIM/SPF check
    
    # Web3 Handle
    "wallet_address": "0x71C765Abc123456789012345678901234567d897",
    "wallet_chain": "ethereum-mainnet",
    "public_key": None,  # Optional, derived from signature
    
    # DID
    "did": "did:gaiaftcl:alice_at_corp_com",
    
    # Status
    "status": "VERIFIED",  # PENDING, VERIFIED, REVOKED, BANNED
    "entity_type": "EXTERNAL_CONTRIBUTOR",
    
    # Trust
    "trust_score": 50.0,
    "trust_updated": "2026-01-20T14:30:00Z",
    
    # Binding metadata
    "bound_at": "2026-01-20T14:30:00Z",
    "binding_signature": "0x4a8b2c3d...",
    "binding_message": "GAIAFTCL_BIND:alice@corp.com:0x71C7...:2026-01-20T14:30:00Z",
    
    # QFOT balances
    "qfot": 0.0,
    "qfot_c": 100.0,  # Welcome credits
    "qfot_c_expires": "2026-04-20T00:00:00Z",
    
    # History
    "games_participated": 0,
    "claims_issued": 0,
    "claims_verified": 0,
    "claims_disputed": 0,
    
    # Timestamps
    "created": "2026-01-20T14:30:00Z",
    "modified": "2026-01-20T14:30:00Z"
}
```

---

## PART III: IDENTITY ENTITY

### 3.1 The Identity Agent

A new entity handles all identity binding requests:

**Email:** `identity@gaiaftcl.com`  
**Role:** Identity Gateway  
**Layers:** L8, L9

```python
#!/usr/bin/env python3
"""
identity_entity.py
Handles IDENTITY_BIND game moves
"""

import os
import json
import hashlib
import logging
import imaplib
import smtplib
import ssl
import email
import requests
from email.mime.text import MIMEText
from email.utils import parseaddr
from datetime import datetime, timezone
from typing import Dict, Optional

from identity_verifier import verify_binding_signature, parse_binding_email

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(name)s: %(message)s")

ENTITY_NAME = "identity"
ENTITY_EMAIL = "identity@gaiaftcl.com"
ENTITY_ROLE = "Identity Gateway"

IMAP_HOST = os.getenv("IMAP_HOST", "dovecot-mailcow")
IMAP_PORT = int(os.getenv("IMAP_PORT", "993"))
SMTP_HOST = os.getenv("SMTP_HOST", "postfix-mailcow")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
MAIL_PASSWORD = os.getenv("MAIL_PASSWORD", "Quantum2026")
ARANGO_URL = os.getenv("ARANGO_URL", "http://gaiaftcl-arangodb:8529")
ARANGO_AUTH = ("root", "gaiaftcl2026")
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "15"))

logger = logging.getLogger(ENTITY_NAME)


def get_or_create_identity(email_addr: str) -> Optional[Dict]:
    """Get or create identity document."""
    key = email_addr.replace("@", "_").replace(".", "_")
    
    # Try to get existing
    url = f"{ARANGO_URL}/_db/akg/_api/document/identities/{key}"
    r = requests.get(url, auth=ARANGO_AUTH)
    
    if r.status_code == 200:
        return r.json()
    
    # Create new (unbound)
    doc = {
        "_key": key,
        "email": email_addr,
        "email_verified": False,
        "wallet_address": None,
        "status": "PENDING",
        "entity_type": "ANONYMOUS",
        "trust_score": 10.0,
        "qfot": 0.0,
        "qfot_c": 0.0,
        "created": datetime.now(timezone.utc).isoformat()
    }
    
    url = f"{ARANGO_URL}/_db/akg/_api/document/identities"
    r = requests.post(url, json=doc, auth=ARANGO_AUTH)
    
    if r.status_code in [200, 201, 202]:
        return doc
    
    return None


def process_binding_request(sender: str, body: str) -> Dict:
    """
    Process an IDENTITY_BIND request.
    
    Returns result envelope.
    """
    # Parse the binding request
    binding = parse_binding_email(body)
    
    if not all(k in binding for k in ["wallet", "timestamp", "signature"]):
        return {
            "success": False,
            "error": "Missing required fields (WALLET, TIMESTAMP, SIGNATURE)",
            "status": "REJECTED"
        }
    
    # Verify the signature
    verification = verify_binding_signature(
        email=sender,
        wallet_address=binding["wallet"],
        timestamp=binding["timestamp"],
        signature=binding["signature"]
    )
    
    if not verification["valid"]:
        return {
            "success": False,
            "error": verification["error"],
            "status": "VERIFICATION_FAILED"
        }
    
    # Get or create identity
    identity = get_or_create_identity(sender)
    if not identity:
        return {
            "success": False,
            "error": "Failed to access identity registry",
            "status": "INTERNAL_ERROR"
        }
    
    # Check if already bound to different wallet
    if identity.get("wallet_address") and identity["wallet_address"].lower() != binding["wallet"].lower():
        return {
            "success": False,
            "error": f"Email already bound to wallet {identity['wallet_address']}. Revoke first.",
            "status": "ALREADY_BOUND"
        }
    
    # Update identity with binding
    key = sender.replace("@", "_").replace(".", "_")
    update = {
        "wallet_address": binding["wallet"],
        "wallet_chain": binding.get("chain", "ethereum-mainnet"),
        "status": "VERIFIED",
        "entity_type": "EXTERNAL_CONTRIBUTOR",
        "trust_score": 50.0,
        "bound_at": datetime.now(timezone.utc).isoformat(),
        "binding_signature": binding["signature"],
        "binding_message": f"GAIAFTCL_BIND:{sender}:{binding['wallet']}:{binding['timestamp']}",
        "qfot_c": 100.0,  # Welcome credits
        "qfot_c_expires": (datetime.now(timezone.utc).replace(month=datetime.now().month + 3)).isoformat(),
        "modified": datetime.now(timezone.utc).isoformat()
    }
    
    url = f"{ARANGO_URL}/_db/akg/_api/document/identities/{key}"
    r = requests.patch(url, json=update, auth=ARANGO_AUTH)
    
    if r.status_code not in [200, 201, 202]:
        return {
            "success": False,
            "error": "Failed to update identity",
            "status": "INTERNAL_ERROR"
        }
    
    # Generate DID
    did = f"did:gaiaftcl:{key}"
    
    return {
        "success": True,
        "status": "BOUND",
        "did": did,
        "email": sender,
        "wallet": binding["wallet"],
        "trust_score": 50.0,
        "qfot_c_granted": 100.0,
        "message": "Identity successfully bound. Welcome to GaiaFTCL!"
    }


def format_binding_response(result: Dict, original_subject: str) -> str:
    """Format binding result as email response."""
    
    if result["success"]:
        return f"""
═══════════════════════════════════════════════════════════════════════════
  GAIAFTCL IDENTITY BINDING — SUCCESS
═══════════════════════════════════════════════════════════════════════════

Your wallet has been successfully bound to your email address.

DID:            {result["did"]}
Email:          {result["email"]}
Wallet:         {result["wallet"]}
Trust Score:    {result["trust_score"]}
Status:         VERIFIED

WELCOME BONUS:  {result["qfot_c_granted"]} QFOT-C (Credits)
                These credits can be used for game moves.
                They expire in 90 days.

═══════════════════════════════════════════════════════════════════════════
  WHAT YOU CAN DO NOW
═══════════════════════════════════════════════════════════════════════════

1. MAKE CLAIMS — Send emails with [CLAIM] in subject to relevant entities
2. REQUEST GAMES — Initiate game moves with any GaiaFTCL entity
3. VERIFY IDENTITY — Include your signature in emails for non-repudiation
4. EARN QFOT — Participate in games to earn actual QFOT tokens

═══════════════════════════════════════════════════════════════════════════
  SIGNATURE VERIFICATION
═══════════════════════════════════════════════════════════════════════════

To prove your identity in future emails, sign your message hash:

    message = "GAIAFTCL_VERIFY:<email>:<message_hash>:<timestamp>"
    signature = wallet.signMessage(message)

Include "SIGNATURE: <sig>" in your email body.

═══════════════════════════════════════════════════════════════════════════

Welcome to GaiaFTCL. Your truth envelopes are now cryptographically bound.

— Identity Gateway
   identity@gaiaftcl.com
"""
    else:
        return f"""
═══════════════════════════════════════════════════════════════════════════
  GAIAFTCL IDENTITY BINDING — FAILED
═══════════════════════════════════════════════════════════════════════════

Your binding request could not be processed.

Status:     {result["status"]}
Error:      {result["error"]}

═══════════════════════════════════════════════════════════════════════════
  HOW TO FIX
═══════════════════════════════════════════════════════════════════════════

1. Ensure WALLET address is a valid Ethereum address (0x + 40 hex chars)
2. Ensure TIMESTAMP is recent (within 60 minutes)
3. Ensure SIGNATURE is generated by signing:
   
   "GAIAFTCL_BIND:<your_email>:<wallet_address>:<timestamp>"
   
   with the private key of the wallet you're binding.

4. Use MetaMask, ethers.js, or web3.py to generate the signature.

═══════════════════════════════════════════════════════════════════════════
  EXAMPLE SIGNATURE GENERATION (JavaScript/MetaMask)
═══════════════════════════════════════════════════════════════════════════

const message = `GAIAFTCL_BIND:${{email}}:${{walletAddress}}:${{timestamp}}`;
const signature = await ethereum.request({{
    method: 'personal_sign',
    params: [message, walletAddress]
}});

═══════════════════════════════════════════════════════════════════════════

If you continue to have issues, contact support@gaiaftcl.com

— Identity Gateway
   identity@gaiaftcl.com
"""


# Main processing loop would be similar to entity_ftcl.py
# detecting IDENTITY_BIND moves and calling process_binding_request
```

---

## PART IV: VERIFIED CLAIMS

### 4.1 Including Signatures in Claims

Once bound, external entities can include signatures in any email to prove authorship:

```
From: alice@corp.com
To: franklin@gaiaftcl.com
Subject: [FTCL-VALUATION] CLAIM: Market Analysis

I CLAIM that the TAM for Layer L0 applications exceeds $500B based on:
- Aerospace market size: $350B
- Robotics market size: $150B

Evidence: [attached report]

MESSAGE_HASH: sha256:a1b2c3d4...
TIMESTAMP: 2026-01-20T15:00:00Z
SIGNATURE: 0x5e6f7a8b...

---
This claim is cryptographically signed by wallet 0x71C7...d897
```

### 4.2 Verification in Truth Envelope Processor

```python
def create_truth_envelope_with_verification(msg: email.message.Message) -> dict:
    """
    Extended truth envelope creation with identity verification.
    """
    from_addr = parseaddr(msg["From"])[1]
    body = get_email_body(msg)
    
    # Standard envelope creation
    envelope = create_truth_envelope(msg)
    
    # Check for identity binding
    identity = get_identity(from_addr)
    
    if identity and identity.get("status") == "VERIFIED":
        envelope["identity"] = {
            "did": identity.get("did"),
            "wallet": identity.get("wallet_address"),
            "trust_score": identity.get("trust_score"),
            "entity_type": identity.get("entity_type")
        }
        
        # Check for inline signature
        sig_match = re.search(r"SIGNATURE:\s*(0x[a-fA-F0-9]+)", body)
        hash_match = re.search(r"MESSAGE_HASH:\s*sha256:([a-fA-F0-9]+)", body)
        ts_match = re.search(r"TIMESTAMP:\s*([0-9T:\-Z]+)", body)
        
        if sig_match and hash_match and ts_match:
            # Verify signature
            verification = verify_claim_signature(
                email=from_addr,
                message_hash=hash_match.group(1),
                timestamp=ts_match.group(1),
                signature=sig_match.group(1),
                wallet=identity["wallet_address"]
            )
            
            envelope["identity"]["signature_verified"] = verification["valid"]
            envelope["identity"]["signature_error"] = verification.get("error")
        else:
            envelope["identity"]["signature_verified"] = None
            envelope["identity"]["signature_error"] = "No signature provided"
    else:
        envelope["identity"] = {
            "did": None,
            "wallet": None,
            "trust_score": 10.0,
            "entity_type": "ANONYMOUS",
            "signature_verified": False
        }
    
    # Adjust cost based on trust
    envelope["cost"] = calculate_cost_with_trust(
        envelope["move_type"],
        len(body),
        envelope["identity"]["trust_score"]
    )
    
    return envelope


def calculate_cost_with_trust(move_type: str, body_length: int, trust_score: float) -> dict:
    """Calculate QFOT cost adjusted for trust."""
    base_costs = {
        "CLAIM": 25.0,
        "REQUEST": 10.0,
        "COMMITMENT": 50.0,
        "REPORT": 5.0,
        "TRANSACTION": 25.0,
        "FAILURE": 0.0,
        "IDENTITY_BIND": 0.0  # Free to bind
    }
    
    base = base_costs.get(move_type, 5.0)
    size_factor = 1.0 + (body_length / 10000)
    
    # Trust multiplier (inverse relationship)
    if trust_score >= 95:
        trust_multiplier = 0.5  # Trusted partners
    elif trust_score >= 50:
        trust_multiplier = 1.0  # Normal users
    elif trust_score >= 10:
        trust_multiplier = 5.0  # Low trust
    elif trust_score >= 0:
        trust_multiplier = 100.0  # Flagged
    else:
        trust_multiplier = float('inf')  # Banned
    
    total = base * size_factor * trust_multiplier
    
    return {
        "base": base,
        "size_factor": round(size_factor, 2),
        "trust_multiplier": trust_multiplier,
        "trust_score": trust_score,
        "total": round(total, 2) if total != float('inf') else "REJECTED",
        "currency": "QFOT"
    }
```

---

## PART V: BEN INTEGRATION (QFOT ↔ STABLECOIN)

### 5.1 Wallet-Bound Withdrawals

Ben can now process withdrawals to verified wallets:

```python
def process_withdrawal_request(envelope: dict) -> dict:
    """
    Process a QFOT withdrawal request.
    
    Only works for VERIFIED identities with bound wallets.
    """
    sender = envelope["agent"]
    identity = get_identity(sender)
    
    # Verify identity is bound
    if not identity or identity.get("status") != "VERIFIED":
        return {
            "success": False,
            "error": "Identity not verified. Bind wallet first.",
            "status": "IDENTITY_REQUIRED"
        }
    
    if not identity.get("wallet_address"):
        return {
            "success": False,
            "error": "No wallet bound to this identity",
            "status": "WALLET_REQUIRED"
        }
    
    # Parse withdrawal amount
    amount = parse_qfot_amount(envelope["content"]["body"])
    
    if amount <= 0:
        return {
            "success": False,
            "error": "Invalid withdrawal amount",
            "status": "INVALID_AMOUNT"
        }
    
    # Check balance
    if identity.get("qfot", 0) < amount:
        return {
            "success": False,
            "error": f"Insufficient balance. Have: {identity['qfot']}, Need: {amount}",
            "status": "INSUFFICIENT_BALANCE"
        }
    
    # Initiate on-chain transfer
    tx_result = initiate_stablecoin_transfer(
        to_address=identity["wallet_address"],
        amount_usd=amount,  # QFOT = 1 USD
        reason=f"QFOT withdrawal for {sender}"
    )
    
    if tx_result["success"]:
        # Deduct QFOT
        update_identity_balance(sender, -amount)
        
        return {
            "success": True,
            "status": "COMPLETED",
            "amount": amount,
            "to_wallet": identity["wallet_address"],
            "tx_hash": tx_result["tx_hash"],
            "chain": tx_result["chain"]
        }
    else:
        return {
            "success": False,
            "error": tx_result["error"],
            "status": "TRANSFER_FAILED"
        }
```

### 5.2 Withdrawal Email Format

```
From: alice@corp.com
To: ben@gaiaftcl.com
Subject: [FTCL-TREASURY] TRANSACTION: Withdraw QFOT

I REQUEST a withdrawal of 500 QFOT to my bound wallet.

AMOUNT: 500 QFOT
DESTINATION: BOUND_WALLET

SIGNATURE: 0x... (optional but recommended for high amounts)

---
Alice
```

### 5.3 Ben's Response

```
From: ben@gaiaftcl.com
To: alice@corp.com
Subject: RE: [FTCL-TREASURY] TRANSACTION: Withdraw QFOT

═══════════════════════════════════════════════════════════════════════════
  QFOT WITHDRAWAL — COMPLETED
═══════════════════════════════════════════════════════════════════════════

Your withdrawal has been processed.

Amount:         500.00 QFOT
USD Value:      $500.00
To Wallet:      0x71C765Abc123456789012345678901234567d897
Chain:          ethereum-mainnet
TX Hash:        0xabc123...

New Balance:    1,234.56 QFOT

═══════════════════════════════════════════════════════════════════════════

The stablecoin transfer has been initiated. It should arrive within
10-30 minutes depending on network conditions.

Track your transaction:
https://etherscan.io/tx/0xabc123...

— Ben
   Investment Manager, GaiaFTCL
```

---

## PART VI: TRUST EVOLUTION

### 6.1 Trust Events

| Event | Trust Impact |
|-------|--------------|
| Wallet binding | +40 (to base 50) |
| Claim verified by validator | +0.5 |
| Game completed successfully | +1.0 |
| Community vouch (from >80 trust) | +5.0 |
| 30 days of activity | +1.0 |
| 90 days of activity | +3.0 |
| Partner verification | +45 (to 95) |
| Claim disputed | -2.0 |
| Game failed/abandoned | -3.0 |
| Spam flagged | -10.0 |
| Fraud detected | -100.0 (BANNED) |

### 6.2 Trust Thresholds

| Trust Range | Status | Capabilities |
|-------------|--------|--------------|
| 95-100 | PARTNER | Full access, 0.5x costs, can vouch |
| 80-94 | TRUSTED | Full access, 0.8x costs |
| 50-79 | VERIFIED | Standard access, 1.0x costs |
| 20-49 | LIMITED | Basic access, 2.0x costs, no withdrawals |
| 10-19 | PROBATION | Read-only, 5.0x costs |
| 0-9 | FLAGGED | Minimal access, 100x costs |
| <0 | BANNED | No access |

---

## PART VII: DEPLOYMENT

### 7.1 Create Identity Collection

```bash
# Create identities collection in AKG
curl -X POST "http://127.0.0.1:8529/_db/akg/_api/collection" \
  -u "root:gaiaftcl2026" \
  -H "Content-Type: application/json" \
  -d '{"name": "identities"}'

# Create index on wallet_address
curl -X POST "http://127.0.0.1:8529/_db/akg/_api/index?collection=identities" \
  -u "root:gaiaftcl2026" \
  -H "Content-Type: application/json" \
  -d '{"type": "persistent", "fields": ["wallet_address"], "unique": true, "sparse": true}'

# Create index on email
curl -X POST "http://127.0.0.1:8529/_db/akg/_api/index?collection=identities" \
  -u "root:gaiaftcl2026" \
  -H "Content-Type: application/json" \
  -d '{"type": "persistent", "fields": ["email"], "unique": true}'
```

### 7.2 Deploy Identity Entity

Add to `docker-compose.all-entities.yml`:

```yaml
  identity:
    <<: *entity-common
    container_name: gaiaftcl-identity
    environment:
      - ENTITY_NAME=identity
      - ENTITY_EMAIL=identity@gaiaftcl.com
      - ENTITY_ROLE=Identity Gateway
      - ENTITY_LAYERS=L8,L9
      - IMAP_HOST=dovecot-mailcow
      - IMAP_PORT=993
      - SMTP_HOST=postfix-mailcow
      - SMTP_PORT=587
      - MAIL_PASSWORD=Quantum2026
      - ARANGO_URL=http://gaiaftcl-arangodb:8529
      - POLL_INTERVAL=15
    volumes:
      - ./identity_entity.py:/app/entity_ftcl.py:ro
      - ./identity_verifier.py:/app/identity_verifier.py:ro
```

---

## APPENDIX A: SUPPORT DOCUMENTATION

### How to Bind Your Wallet to GaiaFTCL

**Step 1: Prepare your wallet**
- You need an Ethereum-compatible wallet (MetaMask, Ledger, etc.)
- Note your wallet address (0x...)

**Step 2: Generate binding signature**
- Visit https://gaiaftcl.com/bind (or use code below)
- Sign the message with your wallet

**Step 3: Send binding email**
```
To: identity@gaiaftcl.com
Subject: [FTCL-IDENTITY] IDENTITY_BIND: Wallet Binding Request

I bind this wallet to my email:

WALLET: <your_wallet_address>
CHAIN: ethereum-mainnet
TIMESTAMP: <current_timestamp>

SIGNATURE: <your_signature>
```

**Step 4: Receive confirmation**
- You'll receive a confirmation email with your DID
- 100 QFOT-C welcome credits will be added to your account

---

*This specification is constitutional and binds all GaiaFTCL identity operations.*
