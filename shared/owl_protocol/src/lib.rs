//! Owl Protocol — Zero-PII Cryptographic Identity
//!
//! The Owl identity is a secp256k1 compressed public key.
//! It contains ZERO personally identifiable information.
//!
//! An Owl identity is used to:
//!   - Gate the MOORED cell state (consent check)
//!   - Sign consent records (append-only, encrypted)
//!   - Personalize ADMET computation (CYP450 variants, pharmacogenomics)
//!   - Track CURE records on-chain (pubkey hash only — never a name)
//!
//! What an Owl identity is NOT:
//!   - A name
//!   - An email address
//!   - A medical record number
//!   - A patient identifier
//!   - Any string a human would recognize as belonging to a specific person
//!
//! The Owl pubkey is 33 bytes (secp256k1 compressed), hex-encoded = 66 chars.
//! It starts with 02 or 03 (compressed public key prefix).

/// A secp256k1 compressed public key used as a zero-PII Owl identity.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OwlPubkey(pub String);

impl OwlPubkey {
    /// Validate that a string is a legitimate zero-PII Owl pubkey.
    /// Rejects names, emails, and any non-hexadecimal personal identifiers.
    pub fn from_hex(s: &str) -> Result<Self, OwlError> {
        if s.len() != 66 {
            return Err(OwlError::InvalidLength { got: s.len(), expected: 66 });
        }
        if !s.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(OwlError::NotHex);
        }
        if !s.starts_with("02") && !s.starts_with("03") {
            return Err(OwlError::InvalidPrefix);
        }
        Ok(Self(s.to_string()))
    }

    /// The first 8 chars of the pubkey — safe to log (not linkable to person).
    pub fn short_id(&self) -> &str {
        &self.0[..8]
    }

    /// SHA-256 of the pubkey — used in on-chain references (never the raw pubkey).
    pub fn chain_hash(&self) -> String {
        use sha2::{Sha256, Digest};
        let mut h = Sha256::new();
        h.update(self.0.as_bytes());
        hex::encode(h.finalize())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OwlError {
    InvalidLength { got: usize, expected: usize },
    NotHex,
    InvalidPrefix,
}

/// Consent state for an Owl identity (populated by consent_validity_check).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConsentState {
    Valid,
    Expired,
    Revoked,
}

/// A consent record — stored encrypted with the Owl public key.
/// Contains NO personal information in plaintext.
#[derive(Debug, Clone)]
pub struct ConsentRecord {
    /// Owl public key (not a name).
    pub owl_pubkey:      OwlPubkey,
    /// When consent was granted (Unix ms timestamp — not linked to a name).
    pub granted_at_ms:  u64,
    /// Current consent state.
    pub state:          ConsentState,
    /// Operation scope (e.g., "ADMET_PERSONALIZATION", "BIOMARKER_READ").
    pub scope:          String,
}

impl ConsentRecord {
    pub fn is_valid(&self, now_ms: u64) -> bool {
        self.state == ConsentState::Valid
            && (now_ms - self.granted_at_ms) < 300_000 // 5-minute window
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_pubkey_accepted() {
        let pk = OwlPubkey::from_hex(
            "02a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
        );
        assert!(pk.is_ok());
    }

    #[test]
    fn email_rejected() {
        assert!(OwlPubkey::from_hex("patient@example.com").is_err());
    }

    #[test]
    fn name_rejected() {
        assert!(OwlPubkey::from_hex("Richard Gillespie").is_err());
    }

    #[test]
    fn chain_hash_is_64_hex_chars() {
        let pk = OwlPubkey::from_hex(
            "02a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
        ).unwrap();
        assert_eq!(pk.chain_hash().len(), 64);
    }

    #[test]
    fn consent_expired_after_5_minutes() {
        let pk = OwlPubkey::from_hex(
            "02a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
        ).unwrap();
        let record = ConsentRecord {
            owl_pubkey:    pk,
            granted_at_ms: 0,
            state:         ConsentState::Valid,
            scope:         "ADMET_PERSONALIZATION".to_string(),
        };
        assert!(!record.is_valid(400_000)); // 400 seconds — expired
        assert!(record.is_valid(100_000));   // 100 seconds — valid
    }
}
