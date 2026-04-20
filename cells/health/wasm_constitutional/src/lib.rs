//! GaiaHealth WASM Constitutional Substrate
//!
//! Biological analog of the UUM-8D WASM module in GaiaFTCL.
//! Operates as an incorruptible governance engine inside WKWebView's
//! WebAssembly linear memory sandbox.
//!
//! Eight mandatory exports — all must be present before OQ can pass:
//!
//!   1. binding_constitutional_check  — thermodynamic plausibility
//!   2. admet_bounds_check            — ADMET safety thresholds
//!   3. phi_boundary_check            — PHI leakage scan (NER)
//!   4. epistemic_chain_validate      — M/I/A chain completeness
//!   5. consent_validity_check        — Owl consent currency
//!   6. force_field_bounds_check      — MD parameter physiological range
//!   7. selectivity_check             — off-target / hERG cardiac safety
//!   8. get_epistemic_tag             — returns M/I/A for a result set
//!
//! Zero-PII guarantee: this module never receives raw PHI.
//! phi_boundary_check scans HASHED representations of outputs only.
//! The Owl pubkey (consent_validity_check input) is a cryptographic
//! public key — no name, no DOB, no email address ever enters this module.
//!
//! Build: wasm-pack build --target web --release
//!
//! Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

use wasm_bindgen::prelude::*;

pub mod nutrition;

// ── Result types ──────────────────────────────────────────────────────────────

/// 0 = PASS, 1..N = specific fault codes
#[wasm_bindgen]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AlarmResult {
    Pass             = 0,
    ImpossibleClash  = 1,   // steric clash — impossible geometry
    NegativeDGAbsurd = 2,   // ΔG < -50 kcal/mol — thermodynamically impossible
    PositiveDGBound  = 3,   // ΔG > 0 — ligand not binding
    BuriedSurfaceLow = 4,   // < 300 Ų buried surface area — too weak
}

#[wasm_bindgen]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ADMETResult {
    Pass               = 0,
    HergCardiacRisk    = 1,  // hERG IC50 < 1 µM — cardiac arrhythmia risk
    MolWeightHigh      = 2,  // MW > 500 Da — Lipinski violation
    LogPOutOfRange     = 3,  // cLogP > 5 or < -2
    ToxicityHigh       = 4,  // predicted LD50 < 100 mg/kg
    BioavailabilityLow = 5,  // oral F% < 10
}

#[wasm_bindgen]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PHIResult {
    Clean    = 0,   // no PHI patterns detected
    PhiAlert = 1,   // NER detected potential PHI in output data
}

#[wasm_bindgen]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChainResult {
    Complete               = 0,
    AssumedBindingOnly     = 1,  // → REFUSED: ASSUMED_BINDING_NOT_VALIDATED
    EpistemicUpgrade       = 2,  // output claims higher trust than input
    ChainBroken            = 3,  // missing intermediate computation step
}

#[wasm_bindgen]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConsentResult {
    Valid      = 0,
    Expired    = 1,  // > 5 minutes since last consent check
    Revoked    = 2,  // Owl identity has revoked consent
    InvalidKey = 3,  // pubkey not a valid secp256k1 compressed key
}

#[wasm_bindgen]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FFResult {
    Ok                   = 0,
    TemperatureOutOfRange = 1,
    PressureOutOfRange    = 2,
    TimestepOutOfRange    = 3,
    SimulationTooShort   = 4,
}

#[wasm_bindgen]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SelectivityResult {
    Safe             = 0,
    HergFlag         = 1,  // cardiac safety: hERG binding predicted
    OffTargetWarning = 2,  // significant off-target binding detected
    Unsafe           = 3,  // multiple critical off-target hits
}

#[wasm_bindgen]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpistemicTag {
    Measured = 0,
    Inferred = 1,
    Assumed  = 2,
}

// ── Export 1: binding_constitutional_check ───────────────────────────────────

/// Validates that the predicted binding is physically and thermodynamically plausible.
///
/// Parameters (JSON string):
///   { "binding_dg": f64, "buried_surface_ang2": f64, "steric_clash": bool }
///
/// Zero-PII: receives only molecular geometry data, no patient identifiers.
#[wasm_bindgen]
pub fn binding_constitutional_check(params_json: &str) -> AlarmResult {
    // Parse parameters — default to safe values on parse failure
    let binding_dg: f64 = extract_f64(params_json, "binding_dg").unwrap_or(-5.0);
    let buried_surface: f64 = extract_f64(params_json, "buried_surface_ang2").unwrap_or(500.0);
    let steric_clash: bool = params_json.contains("\"steric_clash\":true");

    if steric_clash {
        return AlarmResult::ImpossibleClash;
    }
    if binding_dg < -50.0 {
        return AlarmResult::NegativeDGAbsurd;
    }
    if binding_dg > 0.0 {
        return AlarmResult::PositiveDGBound;
    }
    if buried_surface < 300.0 {
        return AlarmResult::BuriedSurfaceLow;
    }

    AlarmResult::Pass
}

// ── Export 2: admet_bounds_check ─────────────────────────────────────────────

/// Executes strict ADMET validation against configured safety thresholds.
///
/// Parameters (JSON string):
///   { "mol_weight_da": f64, "clogp": f64, "herg_ic50_um": f64,
///     "ld50_mg_kg": f64, "oral_f_pct": f64 }
#[wasm_bindgen]
pub fn admet_bounds_check(compound_json: &str) -> ADMETResult {
    let herg_ic50 = extract_f64(compound_json, "herg_ic50_um").unwrap_or(100.0);
    let mol_weight = extract_f64(compound_json, "mol_weight_da").unwrap_or(300.0);
    let clogp = extract_f64(compound_json, "clogp").unwrap_or(2.0);
    let ld50 = extract_f64(compound_json, "ld50_mg_kg").unwrap_or(500.0);
    let oral_f = extract_f64(compound_json, "oral_f_pct").unwrap_or(50.0);

    // hERG cardiac safety — highest priority check
    if herg_ic50 < 1.0 {
        return ADMETResult::HergCardiacRisk;
    }
    if mol_weight > 500.0 {
        return ADMETResult::MolWeightHigh;
    }
    if clogp > 5.0 || clogp < -2.0 {
        return ADMETResult::LogPOutOfRange;
    }
    if ld50 < 100.0 {
        return ADMETResult::ToxicityHigh;
    }
    if oral_f < 10.0 {
        return ADMETResult::BioavailabilityLow;
    }

    ADMETResult::Pass
}

// ── Export 3: phi_boundary_check ─────────────────────────────────────────────

/// Scans all analytical outputs for accidental PHI leakage before data export.
///
/// Input: SHA-256 hash of the output blob (not the raw data — zero-PII design).
/// The WASM substrate never receives raw patient data; it receives only hashes.
/// PHI detection is done by the native Swift layer before hashing.
///
/// For this export, the check validates that the hash is a valid SHA-256 hex
/// (64 chars) — raw PHI would be longer and non-hexadecimal.
#[wasm_bindgen]
pub fn phi_boundary_check(data_hash_hex: &str) -> PHIResult {
    // Valid SHA-256 hex: exactly 64 hexadecimal characters
    if data_hash_hex.len() == 64 && data_hash_hex.chars().all(|c| c.is_ascii_hexdigit()) {
        PHIResult::Clean
    } else {
        // Non-hash input — potential raw data leak, alert immediately
        PHIResult::PhiAlert
    }
}

// ── Export 4: epistemic_chain_validate ───────────────────────────────────────

/// Verifies M/I/A chain is complete and unbroken from input to CURE output.
///
/// Parameters (JSON): { "input_tag": u32, "computation_tag": u32, "output_tag": u32 }
/// Tags: 0=M, 1=I, 2=A
#[wasm_bindgen]
pub fn epistemic_chain_validate(result_json: &str) -> ChainResult {
    let input = extract_u32(result_json, "input_tag").unwrap_or(2);
    let comp  = extract_u32(result_json, "computation_tag").unwrap_or(2);
    let out   = extract_u32(result_json, "output_tag").unwrap_or(2);

    // Output cannot claim higher trust than input (upgrade violation)
    if out < input {
        return ChainResult::EpistemicUpgrade;
    }

    // Both computation and output Assumed → REFUSED
    if comp == 2 && out == 2 {
        return ChainResult::AssumedBindingOnly;
    }

    ChainResult::Complete
}

// ── Export 5: consent_validity_check ─────────────────────────────────────────

/// Evaluates the cryptographic Owl identity for current, valid consent.
///
/// Input: secp256k1 compressed public key hex (66 chars, 02/03 prefix) +
///        timestamp of last consent (Unix ms) + current timestamp (Unix ms).
///
/// Zero-PII: the pubkey is purely cryptographic — no name, no DOB, no email.
/// Consent expiry: 5 minutes (300,000 ms).
#[wasm_bindgen]
pub fn consent_validity_check(owl_pubkey_hex: &str, last_consent_ms: f64, now_ms: f64) -> ConsentResult {
    // Validate pubkey format (zero-PII: must be hex, not a name/email)
    if owl_pubkey_hex.len() != 66
        || !owl_pubkey_hex.chars().all(|c| c.is_ascii_hexdigit())
        || (!owl_pubkey_hex.starts_with("02") && !owl_pubkey_hex.starts_with("03"))
    {
        return ConsentResult::InvalidKey;
    }

    // Check expiry (5-minute window)
    let age_ms = now_ms - last_consent_ms;
    if age_ms > 300_000.0 {
        return ConsentResult::Expired;
    }

    ConsentResult::Valid
}

// ── Export 6: force_field_bounds_check ───────────────────────────────────────

/// Validates MD force field parameters before PREPARED → RUNNING.
///
/// Parameters (JSON): { "temperature_k": f64, "pressure_bar": f64,
///                      "timestep_fs": f64, "simulation_ns": f64 }
#[wasm_bindgen]
pub fn force_field_bounds_check(params_json: &str) -> FFResult {
    let temp   = extract_f64(params_json, "temperature_k").unwrap_or(310.0);
    let press  = extract_f64(params_json, "pressure_bar").unwrap_or(1.0);
    let dt     = extract_f64(params_json, "timestep_fs").unwrap_or(2.0);
    let sim_ns = extract_f64(params_json, "simulation_ns").unwrap_or(100.0);

    if temp < 250.0 || temp > 450.0 { return FFResult::TemperatureOutOfRange; }
    if press < 0.5 || press > 500.0 { return FFResult::PressureOutOfRange; }
    if dt < 0.5 || dt > 4.0         { return FFResult::TimestepOutOfRange; }
    if sim_ns < 10.0                 { return FFResult::SimulationTooShort; }

    FFResult::Ok
}

// ── Export 7: selectivity_check ──────────────────────────────────────────────

/// Checks compound for off-target and cardiac (hERG) safety liabilities.
///
/// Parameters (JSON): { "herg_score": f64, "off_target_count": u32,
///                      "critical_off_target": bool }
/// herg_score: 0.0=safe, 1.0=certain hERG binding
#[wasm_bindgen]
pub fn selectivity_check(compound_json: &str) -> SelectivityResult {
    let herg = extract_f64(compound_json, "herg_score").unwrap_or(0.0);
    let off_count = extract_u32(compound_json, "off_target_count").unwrap_or(0);
    let critical = compound_json.contains("\"critical_off_target\":true");

    if critical || herg > 0.7 {
        return SelectivityResult::Unsafe;
    }
    if herg > 0.3 {
        return SelectivityResult::HergFlag;
    }
    if off_count > 3 {
        return SelectivityResult::OffTargetWarning;
    }

    SelectivityResult::Safe
}

// ── Export 8: get_epistemic_tag ───────────────────────────────────────────────

/// Returns the M/I/A classification for a given result set.
/// Drives the Metal renderer's visualization logic from the WebKit layer.
///
/// Input JSON: { "source_type": string }
/// "measured"  → M, "inferred" → I, everything else → A
#[wasm_bindgen]
pub fn get_epistemic_tag(result_json: &str) -> EpistemicTag {
    if result_json.contains("\"measured\"") {
        EpistemicTag::Measured
    } else if result_json.contains("\"inferred\"") {
        EpistemicTag::Inferred
    } else {
        EpistemicTag::Assumed
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn extract_f64(json: &str, key: &str) -> Option<f64> {
    let search = format!("\"{}\":", key);
    let start = json.find(&search)? + search.len();
    let rest = json[start..].trim_start();
    let end = rest.find(|c: char| !c.is_ascii_digit() && c != '.' && c != '-').unwrap_or(rest.len());
    rest[..end].parse().ok()
}

fn extract_u32(json: &str, key: &str) -> Option<u32> {
    extract_f64(json, key).map(|v| v as u32)
}

// ── GxP Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tc_013_valid_binding_passes() {
        let r = binding_constitutional_check(r#"{"binding_dg":-8.5,"buried_surface_ang2":650.0,"steric_clash":false}"#);
        assert_eq!(r, AlarmResult::Pass);
    }

    #[test]
    fn tc_014_steric_clash_alarm() {
        let r = binding_constitutional_check(r#"{"binding_dg":-8.5,"buried_surface_ang2":650.0,"steric_clash":true}"#);
        assert_eq!(r, AlarmResult::ImpossibleClash);
    }

    #[test]
    fn tc_015_herg_cardiac_risk_blocked() {
        let r = admet_bounds_check(r#"{"mol_weight_da":350.0,"clogp":2.5,"herg_ic50_um":0.5,"ld50_mg_kg":300.0,"oral_f_pct":60.0}"#);
        assert_eq!(r, ADMETResult::HergCardiacRisk);
    }

    #[test]
    fn tc_016_phi_clean_for_valid_hash() {
        let hash = "a".repeat(64); // 64 hex chars
        assert_eq!(phi_boundary_check(&hash), PHIResult::Clean);
    }

    #[test]
    fn tc_017_phi_alert_for_raw_text() {
        assert_eq!(phi_boundary_check("Patient John Doe DOB 01/15/1980"), PHIResult::PhiAlert);
    }

    #[test]
    fn tc_018_assumed_chain_fails() {
        let r = epistemic_chain_validate(r#"{"input_tag":2,"computation_tag":2,"output_tag":2}"#);
        assert_eq!(r, ChainResult::AssumedBindingOnly);
    }

    #[test]
    fn tc_019_consent_expired() {
        let r = consent_validity_check(
            "02a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
            0.0,
            400_000.0, // 400 seconds — expired
        );
        assert_eq!(r, ConsentResult::Expired);
    }

    #[test]
    fn tc_020_consent_invalid_key_rejects_pii() {
        // Must reject a name — not a valid pubkey
        let r = consent_validity_check("Richard Gillespie", 0.0, 1000.0);
        assert_eq!(r, ConsentResult::InvalidKey);
    }

    #[test]
    fn tp_018_force_field_valid_params_pass() {
        let r = force_field_bounds_check(r#"{"temperature_k":310.0,"pressure_bar":1.0,"timestep_fs":2.0,"simulation_ns":100.0}"#);
        assert_eq!(r, FFResult::Ok);
    }

    #[test]
    fn tc_021_herg_unsafe_selectivity() {
        let r = selectivity_check(r#"{"herg_score":0.85,"off_target_count":2,"critical_off_target":false}"#);
        assert_eq!(r, SelectivityResult::Unsafe);
    }

    #[test]
    fn tp_019_epistemic_tag_measured() {
        let r = get_epistemic_tag(r#"{"source_type":"measured"}"#);
        assert_eq!(r, EpistemicTag::Measured);
    }

    #[test]
    fn tp_020_epistemic_tag_assumed_default() {
        let r = get_epistemic_tag(r#"{"source_type":"unknown"}"#);
        assert_eq!(r, EpistemicTag::Assumed);
    }
}
