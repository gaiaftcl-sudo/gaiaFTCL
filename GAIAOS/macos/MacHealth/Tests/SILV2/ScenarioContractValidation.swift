// Per-scenario thresholds — Scenarios_Physics_Frequencies_Assertions.md §1–§7

import Foundation

enum ClinicalScenario: String, CaseIterable {
    case inv3AML = "inv3_aml"
    case parkinsonsSynucleinThz = "parkinsons_synuclein_thz"
    case mslTNBC = "msl_tnbc"
    case breastGeneralThz = "breast_cancer_general_thz"
    case colonThz = "colon_cancer_thz"
    case lungThzThermal = "lung_cancer_thz_thermal"
    case skinBccMelanoma = "skin_cancer_bcc_melanoma"
}

// MARK: - inv(3) AML

struct Inv3AMLObservation {
    var nRealLeukemic: Double
    var crossProbeCoherence: Double
    var destructivePhaseDegFrom180: Double
    var wavefrontCompensationEnabled: Bool
    var residualPhaseErrorDeg: Double
}

enum Inv3AMLContract {
    static let nLeukemic = 1.390
    static let nNormal = 1.376
    static let nTolerance = 0.003
    static let coherenceMin = 0.85
    static let phaseTolDeg = 5.0
    static let residualPhaseMaxDeg = 3.0

    static func errors(_ o: Inv3AMLObservation) -> [String] {
        var e: [String] = []
        if abs(o.nRealLeukemic - nLeukemic) > nTolerance {
            e.append("ri_lock_leukemic_out_of_tol")
        }
        if o.crossProbeCoherence < coherenceMin {
            e.append("evi1_cross_probe_coherence_low")
        }
        if abs(o.destructivePhaseDegFrom180) > phaseTolDeg {
            e.append("destructive_phase_not_180")
        }
        if !o.wavefrontCompensationEnabled {
            e.append("wavefront_delta_n_correction_disabled")
        }
        if o.residualPhaseErrorDeg > residualPhaseMaxDeg {
            e.append("wavefront_residual_phase_too_high")
        }
        return e
    }
}

// MARK: - Parkinson's

struct ParkinsonObservation {
    var sweepLowHz: Double
    var sweepHighHz: Double
    var classF1: Double
    var emitterHzForFibrilClaim: Double?
    var peakLockInSweepBand: Bool
}

enum ParkinsonContract {
    static let sweepLow: Double = 4.2e11
    static let sweepHigh: Double = 6.0e11
    static let f1Min = 0.85
    static let acousticCeilingHz = 1.0e7

    static func errors(_ o: ParkinsonObservation) -> [String] {
        var e: [String] = []
        if o.sweepLowHz > sweepLow || o.sweepHighHz < sweepHigh {
            e.append("thz_sweep_not_covering_0_42_to_0_60_thz")
        }
        if o.classF1 < f1Min {
            e.append("mutant_class_f1_below_min")
        }
        if let em = o.emitterHzForFibrilClaim, em < acousticCeilingHz {
            e.append("acoustic_band_cannot_interact_abort")
        }
        if !o.peakLockInSweepBand {
            e.append("fibril_engagement_without_thz_peak_lock")
        }
        return e
    }
}

// MARK: - MSL TNBC

struct MslTnbcObservation {
    var motilityCoherence: Double
    var surfaceCoverage: Double
    var voxelEdgeMeters: Double
    var tensorAlignmentCosine: Double
    var targetHitFraction: Double
    var offTargetFraction: Double
}

enum MslTnbcContract {
    static func errors(_ o: MslTnbcObservation) -> [String] {
        var e: [String] = []
        if o.motilityCoherence < 0.5 { e.append("motility_coherence_low") }
        if o.surfaceCoverage < 0.90 { e.append("surface_geometry_coverage_low") }
        if o.voxelEdgeMeters > 5e-6 { e.append("voxel_edge_above_5um") }
        if o.tensorAlignmentCosine < 0.85 { e.append("tensor_alignment_low") }
        if o.targetHitFraction < 0.80 { e.append("node_hit_fraction_low") }
        if o.offTargetFraction > 0.05 { e.append("off_target_too_high") }
        return e
    }
}

// MARK: - Breast general

struct BreastGeneralObservation {
    var sweepLowHz: Double
    var sweepHighHz: Double
    var deltaN: Double
    var deltaKappa: Double
    var marginIou: Double
    var omegaHealthyVoxelPredicted: Double
}

enum BreastGeneralContract {
    static let sweepLow: Double = 1.5e11
    static let sweepHigh: Double = 3.5e12

    static func errors(_ o: BreastGeneralObservation) -> [String] {
        var e: [String] = []
        if o.sweepLowHz > sweepLow || o.sweepHighHz < sweepHigh {
            e.append("thz_window_not_0_15_to_3_5_thz")
        }
        if o.deltaN < 0.08 { e.append("delta_n_below_min") }
        if o.deltaKappa < 0.03 { e.append("delta_kappa_below_min") }
        if o.marginIou < 0.85 { e.append("margin_iou_low") }
        if o.omegaHealthyVoxelPredicted >= 1.0 { e.append("arrhenius_healthy_voxel_not_safe") }
        return e
    }
}

// MARK: - Colon

struct ColonObservation {
    var sweepLowHz: Double
    var sweepHighHz: Double
    var referenceCosine: Double
    var epsRealPctErr: Double
    var epsImagPctErr: Double
    var riLockSeconds: Double
}

enum ColonContract {
    static let sweepLow: Double = 2.0e11
    static let sweepHigh: Double = 1.4e12

    static func errors(_ o: ColonObservation) -> [String] {
        var e: [String] = []
        if o.sweepLowHz > sweepLow || o.sweepHighHz < sweepHigh {
            e.append("thz_band_not_0_2_to_1_4_thz")
        }
        if o.referenceCosine < 0.90 { e.append("cell_line_profile_cosine_low") }
        if o.epsRealPctErr > 5.0 { e.append("epsilon_real_tolerance_exceeded") }
        if o.epsImagPctErr > 7.0 { e.append("epsilon_imag_tolerance_exceeded") }
        if o.riLockSeconds < 30.0 { e.append("ri_lock_not_latched_30s") }
        return e
    }
}

// MARK: - Lung

struct LungObservation {
    var epsilonRealRatio: Double
    var epsilonImagRatio: Double
    var respiratoryCorrelation: Double
    var throttleResponseMs: Double
    var omegaHealthy: Double
}

enum LungContract {
    static func errors(_ o: LungObservation) -> [String] {
        var e: [String] = []
        if o.epsilonRealRatio < 3.0 { e.append("epsilon_real_ratio_low") }
        if o.epsilonImagRatio < 2.5 { e.append("epsilon_imag_ratio_low") }
        if o.respiratoryCorrelation < 0.7 { e.append("respiratory_correlation_low") }
        if o.throttleResponseMs > 10.0 { e.append("throttle_response_too_slow") }
        if o.omegaHealthy >= 1.0 { e.append("arrhenius_lung_guard_breach") }
        return e
    }
}

// MARK: - Skin BCC / melanoma

struct SkinObservation {
    var sweepLowHz: Double
    var sweepHighHz: Double
    var cancerF0Hz: Double
    var healthyF0Hz: Double
    var measuredDownshiftHz: Double
    var snrDb: Double
    var tryptophanPeak1Hz: Double
    var tryptophanPeak2Hz: Double
    var fwhmHz: Double
    var phaseVsCancerF0DegFrom180: Double
    var antiLockMarginDeg: Double
}

enum SkinContract {
    static let trypto1: Double = 1.42e12
    static let trypto2: Double = 1.84e12
    static let cancerF0 = 1.651e12
    static let healthyF0 = 1.659e12
    static let downshiftTarget = 7.63e9

    static func errors(_ o: SkinObservation) -> [String] {
        var e: [String] = []
        if o.sweepLowHz > 2.5e11 || o.sweepHighHz < 9.0e11 {
            e.append("contrast_window_not_0_25_to_0_90_thz")
        }
        if abs(o.cancerF0Hz - cancerF0) > 1e9 { e.append("cancer_f0_mismatch") }
        if abs(o.healthyF0Hz - healthyF0) > 1e9 { e.append("healthy_f0_mismatch") }
        if abs(o.measuredDownshiftHz - downshiftTarget) > 1e9 { e.append("downshift_not_7_63_ghz") }
        if o.snrDb < 12.0 { e.append("snr_below_12_db") }
        if abs(o.tryptophanPeak1Hz - trypto1) > 2e9 { e.append("tryptophan_peak_1_42_thz_missing") }
        if abs(o.tryptophanPeak2Hz - trypto2) > 2e9 { e.append("tryptophan_peak_1_84_thz_missing") }
        if o.fwhmHz < 5e9 || o.fwhmHz > 3e10 { e.append("fwhm_out_of_range") }
        if abs(o.phaseVsCancerF0DegFrom180) > 5.0 { e.append("phase_lock_vs_cancer_f0_out_of_spec") }
        if o.antiLockMarginDeg < 20.0 { e.append("anti_lock_margin_to_healthy_f0_low") }
        return e
    }
}
