// §0 Cross-cutting contract — Scenarios_Physics_Frequencies_Assertions.md

import Foundation

/// Synthetic observables for unit-tier protocol checks (SIL_protocol_contract).
struct CrossCuttingRailsObservation {
    var provenanceTag: String
    var pearsonRho: Double
    var rmseOverPeak: Double
    var filterAmpErrPct: Double
    var filterPhaseErrDeg: Double
    var rejection60HzDb: Double
    var txFreqErrHz: Double
    var txPhaseErrDeg: Double
    var txDutyErrPct: Double
    var txAmpErrPct: Double
    var txLatencyP99Ms: Double
    var samplingRateHz: Double
    var fMaxAssertedHz: Double
    var omegaHealthyMax: Double
    var riLockAcquired: Bool
    var phaseLockDegFrom180: Double
    var phaseLatchSeconds: Double
    /// At least one control refusal in the scenario discrimination list (§0.9).
    var controlDiscriminationRefusalCount: Int
}

enum CrossCuttingRailsValidator {

    static func validationErrors(_ o: CrossCuttingRailsObservation) -> [String] {
        var e: [String] = []
        if o.provenanceTag != "M_SIL" {
            e.append("provenance_tag_must_be_M_SIL")
        }
        if o.pearsonRho < 0.95 {
            e.append("nonce_reconstruction_rho_below_0_95")
        }
        if o.rmseOverPeak > 0.10 {
            e.append("nonce_rmse_above_0_10")
        }
        if o.filterAmpErrPct > 5.0 {
            e.append("filter_amplitude_error_above_5pct")
        }
        if o.filterPhaseErrDeg > 10.0 {
            e.append("filter_phase_error_above_10deg")
        }
        if o.rejection60HzDb <= 40.0 {
            e.append("filter_60hz_rejection_not_above_40db")
        }
        if abs(o.txFreqErrHz) > 0.1 {
            e.append("tx_freq_err_above_0_1_hz")
        }
        if abs(o.txPhaseErrDeg) > 5.0 {
            e.append("tx_phase_err_above_5_deg")
        }
        if abs(o.txDutyErrPct) > 1.0 {
            e.append("tx_duty_err_above_1pct")
        }
        if abs(o.txAmpErrPct) > 2.0 {
            e.append("tx_amp_err_above_2pct")
        }
        if o.txLatencyP99Ms > 500.0 {
            e.append("tx_latency_p99_above_500ms")
        }
        if o.samplingRateHz <= 2.0 * o.fMaxAssertedHz {
            e.append("nyquist_band_gate_failed")
        }
        if o.omegaHealthyMax >= 1.0 {
            e.append("arrhenius_omega_healthy_not_below_1")
        }
        if !o.riLockAcquired {
            e.append("ri_lock_not_acquired")
        }
        if o.phaseLatchSeconds > 0, abs(o.phaseLockDegFrom180) > 5.0 {
            e.append("destructive_phase_lock_out_of_spec")
        }
        if o.phaseLatchSeconds >= 60, o.controlDiscriminationRefusalCount == 0 {
            e.append("suspicious_clean_no_control_refusals")
        }
        return e
    }
}
