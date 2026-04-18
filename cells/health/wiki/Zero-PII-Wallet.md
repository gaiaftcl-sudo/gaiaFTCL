# Zero-PII Wallet — GaiaHealth Biologit Cell

> **Wallet prefix:** `gaiahealth1`  
> **Location:** `~/.gaiahealth/wallet.key`  
> **File mode:** `0600` (owner read-only, no exceptions)  
> **Regulation:** HIPAA 45 CFR §164 · GDPR Article 9 · ISO 27001  
> **Crate:** `shared/wallet_core`

---

## The Mandate

**No personally identifiable information of any kind may be stored in the GaiaHealth cell wallet.**

This is not a guideline. It is a **hard architectural constraint** enforced at every layer:

1. The IQ installation script (`iq_install.sh`) never prompts for personal information
2. The `SovereignWallet::derive()` function accepts only cryptographic inputs
3. The `to_json()` serialiser includes `"pii_stored": false` as a machine-readable assertion
4. The `WalletTests` Swift TestRobit suite (10 tests) asserts absence of 14 PHI patterns
5. The WASM `phi_boundary_check()` export rejects any non-hash input
6. The `OwlPubkey::from_hex()` validator rejects names, emails, and any non-hex string

---

## What Is In The Wallet

The wallet contains **only mathematical values** derived from hardware entropy:

```
cell_id        = SHA-256(hw_uuid | entropy | timestamp)
wallet_address = "gaiahealth1" + hex(SHA-256(private_entropy | cell_id))[0..38]
private_entropy = 32 bytes random hex (from openssl rand)
generated_at   = UTC timestamp (ISO 8601) — not linked to any person
```

**Wallet JSON (`~/.gaiahealth/wallet.key`):**

```json
{
  "cell_id": "a3f2...1e9c",
  "wallet_address": "gaiahealth1a3f2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9",
  "private_entropy": "<64 hex chars>",
  "generated_at": "2026-04-16T12:00:00Z",
  "curve": "secp256k1",
  "derivation": "SHA256(hw_uuid|entropy|timestamp)",
  "pii_stored": false,
  "warning": "KEEP SECRET — never commit, never share. Zero personal information stored."
}
```

---

## What Is NOT In The Wallet

The following are **categorically prohibited** from appearing anywhere in the wallet file:

| Category | Examples |
|----------|----------|
| Names | First name, last name, middle name, username |
| Contact | Email address, phone number, postal address |
| Identity | Social Security Number (SSN), passport number, national ID |
| Medical | Medical Record Number (MRN), patient ID, insurance ID |
| Demographics | Date of birth, age, gender, race, ethnicity |
| Diagnosis | ICD codes, condition names, drug prescriptions |
| Network | IP address, MAC address, device name |
| Any human-readable identifier | Any string a person would recognise as belonging to a specific individual |

---

## Derivation Algorithm

```
Step 1: Generate entropy
  entropy = openssl rand -hex 32
  hw_uuid = ioreg -d2 -c IOPlatformExpertDevice | ... (anonymous hardware UUID)
  timestamp = date -u +"%Y%m%dT%H%M%SZ"

Step 2: Derive cell_id
  cell_id = SHA-256(hw_uuid || "|" || entropy || "|" || timestamp)
            → 64 hex chars

Step 3: Derive wallet_address
  addr_hash = SHA-256(entropy || "|" || cell_id)
  wallet_address = "gaiahealth1" + addr_hash[0..38]
                 → total length ≥ 49 chars

Step 4: Write wallet.key
  chmod 600 ~/.gaiahealth/wallet.key
  → JSON with pii_stored: false
```

The wallet address is **mathematically indistinguishable** from any other cryptographic address. It could belong to any system or no system. It is not linkable to a person without access to the private entropy, which is itself non-personal.

---

## Owl Protocol Integration

The Owl Protocol adds a **second layer of zero-PII identity** — the `OwlPubkey`. This is a secp256k1 compressed public key (66 hex chars) used for:

- Gating the MOORED state (consent check)
- Signing consent records (append-only, encrypted)
- Personalising ADMET computation (CYP450 variants — opaque, non-personal)
- Recording CURE events on-chain (SHA-256 hash only, never the raw pubkey)

```
OwlPubkey = 33 bytes secp256k1 compressed pubkey
           = 66 hex chars
           = starts with "02" or "03"
```

**The Owl pubkey is NOT:**
- A name
- An email
- A medical record number
- A patient identifier
- Any string a human would recognise as belonging to a specific person

**Consent expiry:** `ConsentRecord.is_valid(now_ms)` expires after 5 minutes (300,000 ms). The operator must re-consent for each computation session.

---

## Enforcement Layers

### Layer 1 — IQ Script (`iq_install.sh`)

```bash
# Phase 3 of IQ install:
# The script generates all wallet material from hardware entropy.
# It NEVER asks for:
#   - Your name
#   - Your email
#   - Your date of birth
#   - Any personal information whatsoever
```

### Layer 2 — Rust `SovereignWallet::derive()`

```rust
pub fn derive(
    hw_uuid:    &str,   // hardware UUID — anonymous
    entropy:    &str,   // random bytes — not personal
    timestamp:  &str,   // UTC timestamp — not personal
    cell_type:  CellType,
) -> Self { ... }
```

The function signature accepts no personal information. There is no parameter for a name, email, or identifier.

### Layer 3 — Rust `SovereignWallet::to_json()`

```rust
// Always writes:
"pii_stored": false
// Never writes:
// "name", "email", "dob", "ssn", "mrn", "patient"
```

Tested by `wallet_json_has_no_personal_fields` in `shared/wallet_core/src/lib.rs`.

### Layer 4 — Swift WalletTests (10 tests)

The `WalletTests` suite in the Swift TestRobit reads `~/.gaiahealth/wallet.key` and asserts absence of 14 PHI patterns:

```swift
let phiPatterns = [
    "name", "email", "dob", "ssn", "mrn", "patient",
    "insurance", "address", "phone", "birth", "gender",
    "race", "ethnicity", "diagnosis"
]
for pattern in phiPatterns {
    XCTAssertFalse(walletJson.lowercased().contains(pattern))
}
```

### Layer 5 — WASM `phi_boundary_check()`

```rust
// Accepts: 64-char hex SHA-256 hashes
// Rejects: SSN patterns, email addresses, names (non-hex chars)
#[wasm_bindgen]
pub fn phi_boundary_check(input: &str) -> PHIResult { ... }
```

### Layer 6 — Owl `moor_owl()` Validation

```rust
// moor_owl() calls OwlPubkey::from_hex() which:
// - Requires exactly 66 hex chars
// - Requires "02" or "03" prefix
// - Rejects "patient@example.com" → OwlError::NotHex
// - Rejects "Richard Gillespie" → OwlError::InvalidLength
```

---

## File Security

```
~/.gaiahealth/
├── wallet.key      # mode 600 — owner read-only
└── consent/        # mode 700 — owner only
    └── *.json      # consent records, encrypted with Owl pubkey
```

**Never commit `wallet.key` to git.** The `.gitignore` in `cells/health/` excludes `*.key` and `evidence/` by default.

---

## Comparison: Fusion Cell vs Biologit Cell Wallets

| Aspect | GaiaFTCL (Fusion) | GaiaHealth (Biologit) |
|--------|-------------------|----------------------|
| Prefix | `gaia1` | `gaiahealth1` |
| Location | `~/.gaiaftcl/wallet.key` | `~/.gaiahealth/wallet.key` |
| `cell_id` derivation | SHA-256(hw | entropy | ts) | SHA-256(hw | entropy | ts) — same algorithm |
| `pii_stored` field | `false` | `false` |
| PHI prohibited | Yes (all same categories) | Yes (all same categories) |
| Shared crate | `shared/wallet_core` | `shared/wallet_core` |
| `CellType` | `CellType::Fusion` | `CellType::Biologit` |

---

## Regulatory References

| Regulation | Requirement addressed |
|------------|----------------------|
| HIPAA 45 CFR §164.514 | De-identification of PHI — wallet contains no PHI by design |
| GDPR Article 9 | Special category health data — zero-collection architecture |
| ISO 27001 A.8.2 | Information classification — `pii_stored: false` machine-readable |
| FDA 21 CFR Part 11 | Electronic records — audit trail uses pubkey hash only |
| FAIR Data Principles | Findable/Accessible/Interoperable/Reusable — pseudonymous by design |
