# IQ — Installation Qualification — GaiaHealth Biologit Cell

> **Script:** `GaiaHealth/scripts/iq_install.sh`  
> **GAMP Phase:** IQ (Phase 2 of 4)  
> **Receipt:** `evidence/iq_receipt.json`  
> **Prerequisite:** DQ complete (design approved)  
> **Required before:** OQ

---

## Purpose

The Installation Qualification (IQ) verifies that GaiaHealth is **correctly installed in the target environment**, that all cryptographic prerequisites are present, that the sovereign wallet is provisioned with **zero personally identifiable information**, and that all Rust crates compile and their GxP tests pass.

---

## Running the IQ

```bash
cd FoT8D/GaiaHealth
chmod +x scripts/iq_install.sh
./scripts/iq_install.sh
```

The script is **non-interactive by design**. It never asks for personal information. The only operator interaction required is:

1. Providing an Owl pubkey for license acceptance (Phase 6)
2. Reviewing and confirming the printed receipt (Phase 7)

---

## IQ Phases

### Phase 1 — Prerequisites

Checks that all required tools are installed and meet minimum versions:

| Tool | Minimum Version | Check |
|------|----------------|-------|
| Rust (rustup) | 1.75.0 | `rustc --version` |
| wasm-pack | any | `wasm-pack --version` |
| Xcode Command Line Tools | 15.0 | `xcode-select -p` |
| openssl | any | `openssl version` |
| cargo | 1.75.0 | `cargo --version` |

**Failure:** Any missing tool prints instructions to install it and exits with code 1.

---

### Phase 2 — macOS + Metal Check

Verifies the target platform meets GaiaHealth requirements:

- **macOS ≥ 14.0 (Sonoma)** — required for latest Metal 3 features
- **Metal GPU available** — `system_profiler SPDisplaysDataType` checks for Metal
- **No virtual machine** — Metal is unavailable in most VM environments; IQ will warn but not fail

---

### Phase 3 — Zero-PII Wallet Provisioning

This is the most critical IQ phase. The wallet is generated from **pure cryptographic entropy** — no personal information is requested or stored.

```bash
# What the script collects (all non-personal):
HW_UUID=$(ioreg -d2 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')
ENTROPY=$(openssl rand -hex 32)
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")

# What the script NEVER asks for:
# - Your name
# - Your email address  
# - Your date of birth
# - Any medical record number
# - Any insurance identifier
# - Any personal information whatsoever
```

**Wallet output:**
```
~/.gaiahealth/wallet.key   (mode 600 — owner read-only)
```

**Wallet contents:**
```json
{
  "cell_id": "<sha256 of hw_uuid|entropy|timestamp>",
  "wallet_address": "gaiahealth1<38 hex chars>",
  "private_entropy": "<64 hex chars>",
  "generated_at": "<UTC ISO8601>",
  "curve": "secp256k1",
  "derivation": "SHA256(hw_uuid|entropy|timestamp)",
  "pii_stored": false,
  "warning": "KEEP SECRET — never commit, never share. Zero personal information stored."
}
```

**Verification:** The script immediately reads back the wallet and verifies:
- `wallet_address` starts with `gaiahealth1`
- File mode is `0600`
- `pii_stored` = `false`
- No prohibited patterns in JSON (name, email, ssn, mrn, dob, patient)

---

### Phase 4 — WASM Constitutional Build

Builds the `wasm_constitutional` crate to the WebAssembly target:

```bash
cd wasm_constitutional
wasm-pack build --target web
```

**Output verified:**
- `pkg/gaia_health_substrate.js` exists
- `pkg/gaia_health_substrate_bg.wasm` exists
- WASM binary size < 500 KB (constitutional substrate should be minimal)

---

### Phase 5 — Cargo Build and GxP Tests

Builds all four Rust crates and runs all GxP tests:

```bash
cargo build --release
cargo test -- --test-output immediate
```

**Expected:** All 38 Rust GxP tests pass. The test IDs are verified against the canonical list:

| Crate | Tests | Series |
|-------|-------|--------|
| `biologit_md_engine` | 21 | IQ, TP, TN, TC, TI |
| `biologit_usd_parser` | 10 | TP, TN, RG |
| `gaia-health-renderer` | 5 | TP, TC, RG |
| `wasm_constitutional` | 16 (unit) | TC |
| **Total** | **38** | |

**Failure:** Any test failure halts the IQ and prints the failing test ID. IQ cannot be marked PASS until all 38 pass.

---

### Phase 6 — License Acceptance

The operator provides their Owl pubkey to formally accept the software license:

```
Enter your Owl pubkey to accept the GaiaHealth license:
(66-char hex string starting with 02 or 03)
> 
```

The pubkey is validated by `OwlPubkey::from_hex()`:
- Must be exactly 66 hex characters
- Must start with `02` or `03`
- Emails, names, or any non-hex string → rejected with clear error message

**The Owl pubkey is stored as a SHA-256 hash only** in the IQ receipt. The raw pubkey is never written to disk.

---

### Phase 7 — IQ Receipt

On successful completion of all prior phases, the IQ receipt is written:

```bash
mkdir -p evidence/
cat > evidence/iq_receipt.json << EOF
{
  "phase": "IQ",
  "cell": "GaiaHealth-Biologit",
  "gamp_category": 5,
  "timestamp": "${TIMESTAMP}",
  "macos_version": "${MACOS_VER}",
  "rust_version": "${RUST_VER}",
  "cargo_tests_passed": 38,
  "cargo_tests_failed": 0,
  "wasm_build_success": true,
  "wallet_address": "${WALLET_ADDRESS}",
  "pii_stored": false,
  "owl_pubkey_hash": "${OWL_HASH}",
  "status": "PASS"
}
EOF
```

**Receipt location:** `GaiaHealth/evidence/iq_receipt.json`

---

## IQ Exit Criteria

All of the following must be true for IQ to pass:

- [ ] Rust ≥ 1.75 installed
- [ ] wasm-pack installed
- [ ] Xcode ≥ 15 installed
- [ ] macOS ≥ 14.0 confirmed
- [ ] Metal GPU available
- [ ] Wallet provisioned at `~/.gaiahealth/wallet.key` (mode 600)
- [ ] `wallet_address` starts with `gaiahealth1`
- [ ] `pii_stored: false` in wallet JSON
- [ ] No PHI patterns in wallet JSON
- [ ] WASM build succeeded (both .js and .wasm present)
- [ ] All 38 Rust GxP tests pass (0 failures)
- [ ] Owl pubkey accepted by `from_hex()` validation
- [ ] `evidence/iq_receipt.json` written with `"status": "PASS"`

---

## Common IQ Failures

| Failure | Cause | Resolution |
|---------|-------|-----------|
| `Rust version too old` | rustc < 1.75 | `rustup update stable` |
| `Metal not available` | Running in VM or headless | Requires physical Mac with Metal GPU |
| `Wallet mode not 600` | `umask` issue | `chmod 600 ~/.gaiahealth/wallet.key` |
| `PHI detected in wallet` | Manual wallet edit introduced personal data | Delete wallet, re-run IQ Phase 3 |
| `OwlPubkey rejection` | Provided email/name instead of pubkey | Generate a secp256k1 keypair; provide compressed pubkey |
| `GxP test failure` | Code regression | Check failing test ID; fix before re-running IQ |
| `WASM build failure` | wasm32 target not installed | `rustup target add wasm32-unknown-unknown` |

---

## Next Step

After IQ PASS → proceed to **[OQ — Operational Qualification](./OQ-Operational-Qualification.md)**
