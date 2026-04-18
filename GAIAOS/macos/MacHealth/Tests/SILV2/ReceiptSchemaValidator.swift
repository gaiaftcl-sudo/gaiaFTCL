// Receipt schema §10 — Scenarios_Physics_Frequencies_Assertions.md
// Validates structural completeness for OQ ingest (protocol contract tier).

import Foundation

enum ReceiptSchemaValidator {

    /// Top-level keys required before ingest; missing any → REFUSED.
    static let mandatoryRootKeys: [String] = [
        "scenario",
        "run_id",
        "nonce_128bit_hex",
        "provenance_tag",
        "plant_config_sha256",
        "substrate_sha256",
        "engine_sha256",
        "wasm_sha256",
        "sweep_window_hz",
        "ri_lock",
        "resonance_detection",
        "destructive_interference",
        "arrhenius",
        "nonce_reconstruction",
        "filter_envelope",
        "tx_envelope",
        "asserts",
        "refusals",
        "control_discrimination",
        "parent_hash",
        "receipt_sig",
    ]

    /// Nested object keys each block must include for structural completeness.
    private static let nestedBlockRequirements: [String: [String]] = [
        "ri_lock": ["n_real", "k_imag", "target_n", "target_k", "locked_duration_s", "passed"],
        "resonance_detection": ["f0_hz", "fwhm_hz", "snr_db", "passed"],
        "destructive_interference": ["phase_deg_vs_f0", "anti_lock_margin_deg", "latched_duration_s", "passed"],
        "arrhenius": ["tissue", "Ea_kJ_mol", "omega_max_observed", "predicted_vs_observed_delta", "throttle_events", "passed"],
        "nonce_reconstruction": ["pearson_rho", "rmse_over_peak", "window_s", "passed"],
        "filter_envelope": ["amplitude_error_pct", "phase_error_deg", "rejection_60hz_db", "passed"],
        "tx_envelope": ["freq_err_hz", "phase_err_deg", "duty_err_pct", "amp_err_pct", "latency_p99_ms", "passed"],
    ]

    /// Returns human-readable refusal reasons; empty means structurally acceptable.
    static func validationErrors(_ receipt: [String: Any]) -> [String] {
        var errors: [String] = []
        for key in mandatoryRootKeys {
            if receipt[key] == nil {
                errors.append("REFUSED:missing_block:\(key)")
            }
        }
        for (block, keys) in nestedBlockRequirements {
            guard let obj = receipt[block] as? [String: Any] else { continue }
            for k in keys where obj[k] == nil {
                errors.append("REFUSED:missing_field:\(block).\(k)")
            }
        }
        if let tag = receipt["provenance_tag"] as? String, tag != "M_SIL" {
            errors.append("REFUSED:provenance_not_M_SIL")
        }
        return errors
    }

    static func isIngestible(_ receipt: [String: Any]) -> Bool {
        validationErrors(receipt).isEmpty
    }
}
