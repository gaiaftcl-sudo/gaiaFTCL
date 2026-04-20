//! OWL-NUTRITION projection exports — versioned, deterministic stubs [I full DRI/CAB integration].
use hex;
use sha2::{Digest, Sha256};
use wasm_bindgen::prelude::*;

const VERSION: &str = "0.1.0";

/// Semantic version for nutrition WASM bundle (embedded in every receipt JSON).
#[wasm_bindgen]
pub fn nutrition_projection_wasm_version() -> String {
    VERSION.to_string()
}

/// Single entry for all mother invariants — `mother_id` e.g. OWL-NUTRITION-MACRO-001.
#[wasm_bindgen]
pub fn project_nutrition_invariant(mother_id: &str, evidence_json: &str) -> String {
    format!(
        r#"{{"nutrition_wasm_version":"{}","mother_id":{},"terminal":"HELD","epistemic":"T","evidence_bytes":{}}}"#,
        VERSION,
        serde_json::to_string(mother_id).unwrap_or_else(|_| "\"\"".to_string()),
        evidence_json.len()
    )
}

/// 0 = no violation, 1 = C4 filter would reject / require user confirm.
#[wasm_bindgen]
pub fn nutrition_c4_violation_check(filters_json: &str, food_event_json: &str) -> u32 {
    let f = filters_json.to_lowercase();
    let food = food_event_json.to_lowercase();
    if f.contains("vegan") && (food.contains("chicken") || food.contains("pork") || food.contains("beef")) {
        return 1;
    }
    if f.contains("kosher") && food.contains("pork") {
        return 1;
    }
    0
}

/// Deterministic SHA-256 over canonical UTF-8 bytes — audit pipeline pre-sign digest (see `AUDIT_EVENT_ROUTING.md`).
#[wasm_bindgen]
pub fn nutrition_audit_event_digest(canonical_event_json: &str) -> String {
    let mut h = Sha256::new();
    h.update(canonical_event_json.as_bytes());
    let out = h.finalize();
    format!(
        r#"{{"digest_kind":"sha256","hex":"{}"}}"#,
        hex::encode(out)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adversarial_vegan_chicken_violation() {
        let f = r#"{"ethical_framework":{"enum_id":"vegan"}}"#;
        let ev = r#"{"food":"chicken breast"}"#;
        assert_eq!(nutrition_c4_violation_check(f, ev), 1);
    }

    #[test]
    fn kosher_pork_violation() {
        let f = r#"{"religious_framework":{"enum_id":"kosher"}}"#;
        let ev = r#"{"food":"pork"}"#;
        assert_eq!(nutrition_c4_violation_check(f, ev), 1);
    }

    #[test]
    fn projection_json_includes_version() {
        let s = project_nutrition_invariant("OWL-NUTRITION-MACRO-001", "{}");
        assert!(s.contains("nutrition_wasm_version"));
    }

    #[test]
    fn audit_digest_sha256_deterministic() {
        let payload = r#"{"event_class":"food_log","seq":1}"#;
        let a = nutrition_audit_event_digest(payload);
        let b = nutrition_audit_event_digest(payload);
        assert_eq!(a, b);
        assert!(a.contains("digest_kind\":\"sha256"));
    }

    #[test]
    fn audit_digest_known_empty_vector() {
        let s = nutrition_audit_event_digest("");
        assert!(s.contains("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
    }

    #[test]
    fn audit_digest_changes_with_payload() {
        let x = nutrition_audit_event_digest("a");
        let y = nutrition_audit_event_digest("b");
        assert_ne!(x, y);
    }
}
