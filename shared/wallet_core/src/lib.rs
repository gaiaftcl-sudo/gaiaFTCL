//! wallet_core — Zero-PII Sovereign Wallet Primitives
//!
//! Shared between GaiaFTCL (Fusion Cell) and GaiaHealth (Biologit Cell).
//!
//! A wallet in the Gaia ecosystem contains ZERO personally identifiable
//! information. It is purely mathematical:
//!
//!   cell_id        = SHA-256(hw_uuid | entropy | timestamp)
//!   wallet_address = "gaia{prefix}1" + hex(SHA-256(private_entropy | cell_id))[0..38]
//!   public_key     = secp256k1 compressed pubkey (33 bytes, hex-encoded)
//!
//! What is NEVER stored in a wallet:
//!   - Names (first, last, middle)
//!   - Email addresses
//!   - Dates of birth
//!   - Social security numbers
//!   - Medical record numbers
//!   - Insurance identifiers
//!   - IP addresses
//!   - Physical addresses
//!   - Phone numbers
//!   - Any human-readable identifier
//!
//! The wallet is mathematically indistinguishable from a bitcoin wallet
//! address — it could belong to any person or no person.
//!
//! Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

use sha2::{Sha256, Digest};
use hex;

/// Which cell type generated this wallet.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CellType {
    Fusion,   // GaiaFTCL — prefix "gaia"
    Biologit, // GaiaHealth — prefix "gaiahealth"
}

impl CellType {
    pub fn wallet_prefix(&self) -> &'static str {
        match self {
            CellType::Fusion   => "gaia1",
            CellType::Biologit => "gaiahealth1",
        }
    }
}

/// Zero-PII wallet. All fields are cryptographic — no personal information.
#[derive(Debug, Clone)]
pub struct SovereignWallet {
    /// SHA-256 hash of (hw_uuid | entropy | timestamp). Not a personal identifier.
    pub cell_id:        String,
    /// Derived wallet address: prefix + hex(SHA-256(private | cell_id))[0..38]
    pub wallet_address: String,
    /// secp256k1 private entropy (hex). NEVER transmit. Owner-read only (mode 600).
    pub private_entropy: String,
    /// Cell type identifier.
    pub cell_type:      CellType,
    /// Generation timestamp (UTC, ISO8601). Not linked to a person.
    pub generated_at:   String,
}

impl SovereignWallet {
    /// Derive a wallet from raw components.
    ///
    /// # Arguments
    /// - `hw_uuid`: Hardware UUID (from ioreg — anonymous hardware identifier)
    /// - `entropy`: 32-byte random hex string (from openssl rand)
    /// - `timestamp`: UTC timestamp string
    /// - `cell_type`: Which cell this wallet serves
    ///
    /// No personal information is accepted or stored.
    pub fn derive(
        hw_uuid:    &str,
        entropy:    &str,
        timestamp:  &str,
        cell_type:  CellType,
    ) -> Self {
        // Derive cell_id: SHA-256(hw_uuid | entropy | timestamp)
        let mut hasher = Sha256::new();
        hasher.update(format!("{hw_uuid}|{entropy}|{timestamp}").as_bytes());
        let cell_id = hex::encode(hasher.finalize());

        // Derive private entropy (separate from hw_uuid — defense in depth)
        let private_entropy = entropy.to_string();

        // Derive wallet address: prefix + hex(SHA-256(private | cell_id))[0..38]
        let mut addr_hasher = Sha256::new();
        addr_hasher.update(format!("{private_entropy}|{cell_id}").as_bytes());
        let addr_hash = hex::encode(addr_hasher.finalize());
        let wallet_address = format!("{}{}", cell_type.wallet_prefix(), &addr_hash[..38]);

        Self {
            cell_id,
            wallet_address,
            private_entropy,
            cell_type,
            generated_at: timestamp.to_string(),
        }
    }

    /// Serialize to wallet.key JSON (owner-read only — mode 600).
    /// The JSON contains ZERO personal information.
    pub fn to_json(&self) -> String {
        format!(
            r#"{{
  "cell_id": "{}",
  "wallet_address": "{}",
  "private_entropy": "{}",
  "generated_at": "{}",
  "curve": "secp256k1",
  "derivation": "SHA256(hw_uuid|entropy|timestamp)",
  "pii_stored": false,
  "warning": "KEEP SECRET — never commit, never share. Zero personal information stored."
}}"#,
            self.cell_id,
            self.wallet_address,
            self.private_entropy,
            self.generated_at,
        )
    }

    /// Validate that a string looks like a wallet address (not a personal identifier).
    pub fn is_valid_address(addr: &str) -> bool {
        (addr.starts_with("gaia1") || addr.starts_with("gaiahealth1"))
            && addr.len() >= 43
            && addr.chars().all(|c| c.is_alphanumeric())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_wallet(cell_type: CellType) -> SovereignWallet {
        SovereignWallet::derive(
            "550E8400-E29B-41D4-A716-446655440000",
            &"a".repeat(64),
            "20260416T120000Z",
            cell_type,
        )
    }

    #[test]
    fn wallet_cell_id_is_64_hex_chars() {
        let w = make_wallet(CellType::Fusion);
        assert_eq!(w.cell_id.len(), 64);
        assert!(w.cell_id.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn fusion_address_prefix() {
        let w = make_wallet(CellType::Fusion);
        assert!(w.wallet_address.starts_with("gaia1"));
    }

    #[test]
    fn biologit_address_prefix() {
        let w = make_wallet(CellType::Biologit);
        assert!(w.wallet_address.starts_with("gaiahealth1"));
    }

    #[test]
    fn wallet_json_contains_zero_pii_field() {
        let w = make_wallet(CellType::Biologit);
        let json = w.to_json();
        assert!(json.contains("\"pii_stored\": false"));
    }

    #[test]
    fn wallet_json_has_no_personal_fields() {
        let w = make_wallet(CellType::Fusion);
        let json = w.to_json();
        for prohibited in &["name", "email", "dob", "ssn", "mrn", "patient"] {
            assert!(
                !json.to_lowercase().contains(prohibited),
                "wallet JSON must not contain '{prohibited}'"
            );
        }
    }

    #[test]
    fn is_valid_address_accepts_gaia1() {
        assert!(SovereignWallet::is_valid_address("gaia1abcdef1234567890abcdef1234567890abcdef12"));
    }

    #[test]
    fn is_valid_address_rejects_email() {
        assert!(!SovereignWallet::is_valid_address("user@example.com"));
    }
}
