// XCTest — SIL V2 seven-scenario protocol contracts (unit tier).
// Spec: ../../../../../Scenarios_Physics_Frequencies_Assertions.md (repo root)

import XCTest

final class ClinicalScenarioContractTests: XCTestCase {

    // MARK: - §0 Cross-cutting rails

    func testCrossCuttingRails_passingSyntheticObservation() {
        let obs = CrossCuttingRailsObservation(
            provenanceTag: "M_SIL",
            pearsonRho: 0.97,
            rmseOverPeak: 0.06,
            filterAmpErrPct: 2.1,
            filterPhaseErrDeg: 3.8,
            rejection60HzDb: 47,
            txFreqErrHz: 0.03,
            txPhaseErrDeg: 1.9,
            txDutyErrPct: 0.4,
            txAmpErrPct: 0.9,
            txLatencyP99Ms: 212,
            samplingRateHz: 7.1e12,
            fMaxAssertedHz: 3.5e12,
            omegaHealthyMax: 0.4,
            riLockAcquired: true,
            phaseLockDegFrom180: 2.0,
            phaseLatchSeconds: 72,
            controlDiscriminationRefusalCount: 2
        )
        XCTAssertTrue(CrossCuttingRailsValidator.validationErrors(obs).isEmpty)
    }

    // MARK: - Receipt §10

    func testReceiptSchema_ingestibleMinimalPassingPayload() {
        let receipt = Self.sampleReceipt(scenario: ClinicalScenario.inv3AML.rawValue)
        XCTAssertTrue(ReceiptSchemaValidator.isIngestible(receipt), ReceiptSchemaValidator.validationErrors(receipt).joined(separator: "; "))
    }

    func testReceiptSchema_refusedWhenDestructiveInterferenceMissing() {
        var receipt = Self.sampleReceipt(scenario: ClinicalScenario.parkinsonsSynucleinThz.rawValue)
        receipt.removeValue(forKey: "destructive_interference")
        XCTAssertFalse(ReceiptSchemaValidator.isIngestible(receipt))
        XCTAssertTrue(ReceiptSchemaValidator.validationErrors(receipt).contains { $0.contains("destructive_interference") })
    }

    // MARK: - Seven scenarios

    func testInv3AML_contractPassesWithSyntheticPassingObservation() {
        let o = Inv3AMLObservation(
            nRealLeukemic: 1.389,
            crossProbeCoherence: 0.90,
            destructivePhaseDegFrom180: 2.0,
            wavefrontCompensationEnabled: true,
            residualPhaseErrorDeg: 1.5
        )
        XCTAssertTrue(Inv3AMLContract.errors(o).isEmpty, Inv3AMLContract.errors(o).joined(separator: "; "))
    }

    func testParkinsons_contractPassesWithSyntheticPassingObservation() {
        let o = ParkinsonObservation(
            sweepLowHz: 4.0e11,
            sweepHighHz: 6.5e11,
            classF1: 0.88,
            emitterHzForFibrilClaim: nil,
            peakLockInSweepBand: true
        )
        XCTAssertTrue(ParkinsonContract.errors(o).isEmpty)
    }

    func testParkinsons_acousticFibrilClaimAborts() {
        let o = ParkinsonObservation(
            sweepLowHz: 4.2e11,
            sweepHighHz: 6.0e11,
            classF1: 0.90,
            emitterHzForFibrilClaim: 5e6,
            peakLockInSweepBand: true
        )
        XCTAssertEqual(ParkinsonContract.errors(o), ["acoustic_band_cannot_interact_abort"])
    }

    func testMslTnbc_contractPassesWithSyntheticPassingObservation() {
        let o = MslTnbcObservation(
            motilityCoherence: 0.62,
            surfaceCoverage: 0.92,
            voxelEdgeMeters: 4e-6,
            tensorAlignmentCosine: 0.88,
            targetHitFraction: 0.85,
            offTargetFraction: 0.03
        )
        XCTAssertTrue(MslTnbcContract.errors(o).isEmpty)
    }

    func testBreastGeneral_contractPassesWithSyntheticPassingObservation() {
        let o = BreastGeneralObservation(
            sweepLowHz: 1.0e11,
            sweepHighHz: 4.0e12,
            deltaN: 0.10,
            deltaKappa: 0.05,
            marginIou: 0.88,
            omegaHealthyVoxelPredicted: 0.2
        )
        XCTAssertTrue(BreastGeneralContract.errors(o).isEmpty)
    }

    func testColon_contractPassesWithSyntheticPassingObservation() {
        let o = ColonObservation(
            sweepLowHz: 1.9e11,
            sweepHighHz: 1.5e12,
            referenceCosine: 0.92,
            epsRealPctErr: 3.0,
            epsImagPctErr: 6.0,
            riLockSeconds: 35
        )
        XCTAssertTrue(ColonContract.errors(o).isEmpty)
    }

    func testLung_contractPassesWithSyntheticPassingObservation() {
        let o = LungObservation(
            epsilonRealRatio: 3.5,
            epsilonImagRatio: 2.8,
            respiratoryCorrelation: 0.75,
            throttleResponseMs: 8,
            omegaHealthy: 0.3
        )
        XCTAssertTrue(LungContract.errors(o).isEmpty)
    }

    func testSkin_contractPassesWithSyntheticPassingObservation() {
        let o = SkinObservation(
            sweepLowHz: 2.0e11,
            sweepHighHz: 1.0e12,
            cancerF0Hz: 1.651e12,
            healthyF0Hz: 1.659e12,
            measuredDownshiftHz: 7.63e9,
            snrDb: 14,
            tryptophanPeak1Hz: 1.42e12,
            tryptophanPeak2Hz: 1.84e12,
            fwhmHz: 1.2e10,
            phaseVsCancerF0DegFrom180: 3.0,
            antiLockMarginDeg: 22
        )
        XCTAssertTrue(SkinContract.errors(o).isEmpty)
    }

    func testClinicalScenario_allCasesCountIsSeven() {
        XCTAssertEqual(ClinicalScenario.allCases.count, 7)
    }

    // MARK: - Helpers

    private static func sampleReceipt(scenario: String) -> [String: Any] {
        [
            "scenario": scenario,
            "run_id": "00000000-0000-4000-8000-000000000001",
            "nonce_128bit_hex": "00112233445566778899aabbccddeeff",
            "provenance_tag": "M_SIL",
            "plant_config_sha256": "deadbeef01",
            "substrate_sha256": "deadbeef02",
            "engine_sha256": "deadbeef03",
            "wasm_sha256": "deadbeef04",
            "sweep_window_hz": [1.5e11, 3.5e12],
            "ri_lock": [
                "n_real": 1.39, "k_imag": 0.01, "target_n": 1.39, "target_k": 0.01,
                "locked_duration_s": 65.0, "passed": true,
            ],
            "resonance_detection": [
                "f0_hz": 1e9, "fwhm_hz": 1e8, "snr_db": 20.0, "passed": true,
            ],
            "destructive_interference": [
                "phase_deg_vs_f0": 180.0, "anti_lock_margin_deg": 22.0,
                "latched_duration_s": 65.0, "passed": true,
            ],
            "arrhenius": [
                "tissue": "healthy_marrow_stroma",
                "Ea_kJ_mol": 340,
                "omega_max_observed": 0.4,
                "predicted_vs_observed_delta": 0.05,
                "throttle_events": 0,
                "passed": true,
            ],
            "nonce_reconstruction": [
                "pearson_rho": 0.97,
                "rmse_over_peak": 0.06,
                "window_s": [60, 300],
                "passed": true,
            ],
            "filter_envelope": [
                "amplitude_error_pct": 2.1,
                "phase_error_deg": 3.8,
                "rejection_60hz_db": 47.2,
                "passed": true,
            ],
            "tx_envelope": [
                "freq_err_hz": 0.03,
                "phase_err_deg": 1.9,
                "duty_err_pct": 0.4,
                "amp_err_pct": 0.9,
                "latency_p99_ms": 212,
                "passed": true,
            ],
            "asserts": [[
                "name": "unit_contract",
                "passed": true,
                "observed": [:] as [String: Any],
                "tolerance": [:] as [String: Any],
            ]],
            "refusals": [] as [[String: Any]],
            "control_discrimination": [[
                "control": "control_a",
                "refused": true,
                "reason": "discrimination",
            ]],
            "parent_hash": "00" + String(repeating: "ab", count: 31),
            "receipt_sig": "ed25519_placeholder_unit_tier",
        ]
    }
}
