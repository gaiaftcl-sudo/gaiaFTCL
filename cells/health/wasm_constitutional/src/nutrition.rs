//! OWL-NUTRITION projection exports — versioned, deterministic stubs [I full DRI/CAB integration].
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

/// Shadow log for audit pipeline — append-only consumer [I mesh seal].
#[wasm_bindgen]
pub fn nutrition_audit_event_digest(canonical_event_json: &str) -> String {
    let n = canonical_event_json.len();
    format!("{{\"digest_kind\":\"sha256_stub\",\"input_len\":{}}}", n)
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
}
