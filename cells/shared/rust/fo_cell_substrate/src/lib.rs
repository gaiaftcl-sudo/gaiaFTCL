use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FoWitness {
    pub lg_id: String,
    pub payload_sha256: String,
}

pub fn sha256_hex(input: &[u8]) -> String {
    let digest = Sha256::digest(input);
    digest.iter().map(|b| format!("{:02x}", b)).collect::<String>()
}

pub fn make_witness(lg_id: impl Into<String>, payload: &[u8]) -> FoWitness {
    FoWitness {
        lg_id: lg_id.into(),
        payload_sha256: sha256_hex(payload),
    }
}
