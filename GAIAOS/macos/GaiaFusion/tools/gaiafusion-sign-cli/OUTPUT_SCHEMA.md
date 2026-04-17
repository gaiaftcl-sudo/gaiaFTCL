# gaiafusion-sign-cli Output Schema

**Version:** 1.0.0  
**Purpose:** Cryptographic wallet-based signatures for GAMP 5 validation evidence  
**Compliance:** FDA 21 CFR Part 11 §11.200(b) — biometric/token alternative to username+password

## JSON Envelope Contract

All signatures produced by `gaiafusion-sign-cli` emit a complete JSON envelope suitable for independent verification by CERN reviewers and regulatory auditors.

### Schema

```json
{
  "wallet_pubkey": "string",
  "signature": "string",
  "digest": "string",
  "algorithm": "string",
  "role": "string",
  "meaning": "string",
  "timestamp": "string",
  "founding_wallet": "boolean",
  "verification_command": "string"
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `wallet_pubkey` | string | Hex-encoded P256 public key (uncompressed, 65 bytes = 130 hex chars) |
| `signature` | string | Hex-encoded ECDSA signature (DER format, typically 70-72 bytes) |
| `digest` | string | SHA-256 hash of the signed content (64 hex chars) |
| `algorithm` | string | Always `"ECDSA-P256-SHA256"` for this implementation |
| `role` | string | Operator authorization level: `"L1"`, `"L2"`, or `"L3"` |
| `meaning` | string | Human-readable attestation (e.g., `"IQ validation complete — app bundle verified"`) |
| `timestamp` | string | ISO 8601 timestamp with milliseconds (e.g., `"2026-04-15T12:34:56.789Z"`) |
| `founding_wallet` | boolean | `true` if this is the founding wallet (perpetual license exemption) |
| `verification_command` | string | Complete OpenSSL command for independent signature verification |

### Example Output

```json
{
  "wallet_pubkey": "04a1b2c3d4e5f6...truncated...890abc",
  "signature": "3045022100abc123...truncated...def789",
  "digest": "d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6",
  "algorithm": "ECDSA-P256-SHA256",
  "role": "L3",
  "meaning": "IQ validation complete — app bundle verified",
  "timestamp": "2026-04-15T14:23:17.456Z",
  "founding_wallet": true,
  "verification_command": "openssl dgst -sha256 -verify pubkey.pem -signature sig.der digest.bin"
}
```

## Usage in Validation Scripts

Validation scripts invoke the CLI and extract the full JSON envelope:

```bash
WALLET_SIG=$(tools/gaiafusion-sign-cli/target/release/gaiafusion-sign-cli \
  --file evidence/iq_receipt.json \
  --meaning "IQ validation complete — app bundle verified" \
  --role L3)

# Extract fields for HTML report
PUBKEY=$(echo "$WALLET_SIG" | jq -r '.wallet_pubkey')
SIGNATURE=$(echo "$WALLET_SIG" | jq -r '.signature')
DIGEST=$(echo "$WALLET_SIG" | jq -r '.digest')
TIMESTAMP=$(echo "$WALLET_SIG" | jq -r '.timestamp')
```

## Independent Verification

CERN reviewers can verify any signature using only the public key, signature, and digest from the HTML evidence report:

```bash
# Extract public key from JSON envelope
echo "$WALLET_SIG" | jq -r '.wallet_pubkey' | xxd -r -p > pubkey.bin

# Convert to PEM format
openssl ec -pubin -inform DER -in pubkey.bin -outform PEM -out pubkey.pem

# Extract signature
echo "$WALLET_SIG" | jq -r '.signature' | xxd -r -p > sig.der

# Extract digest
echo "$WALLET_SIG" | jq -r '.digest' | xxd -r -p > digest.bin

# Verify
openssl dgst -sha256 -verify pubkey.pem -signature sig.der digest.bin
```

Output: `Verified OK` (signature valid) or `Verification Failure` (signature invalid)

## Audit Trail Integration

Each phase receipt (IQ, OQ, RT, SP, PQ) includes the wallet signature JSON envelope. The HTML evidence report displays all signatures in a table with wallet public key, role, meaning, timestamp, and verification command for each phase.

## Chain Integrity

Phase receipts are cryptographically chained. Each receipt includes:
- SHA-256 of its own content
- SHA-256 of the previous phase's receipt

Resume validation verifies the chain integrity before skipping completed phases.

---

**FortressAI Research Institute**  
Norwich, Connecticut  
USPTO 19/460,960 | USPTO 19/096,071
