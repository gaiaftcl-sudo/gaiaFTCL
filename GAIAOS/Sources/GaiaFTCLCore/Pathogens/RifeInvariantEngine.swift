import Foundation

/// Verdict produced by each Rife invariant check.
public struct RifeVerdict: Codable, Sendable {
    public let invariantId: String
    public let terminalState: TerminalState
    public let message: String
    public let evidence: [String: String]

    public init(invariantId: String, terminalState: TerminalState, message: String, evidence: [String: String] = [:]) {
        self.invariantId = invariantId
        self.terminalState = terminalState
        self.message = message
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case invariantId = "invariant_id"
        case terminalState = "terminal_state"
        case message
        case evidence
    }
}

/// Composite verdict returned by the full invariant suite.
public struct RifeSuiteVerdict: Codable, Sendable {
    public let pathogenId: String
    public let terminalState: TerminalState
    public let verdicts: [RifeVerdict]
    public let authorizedForEmission: Bool

    enum CodingKeys: String, CodingKey {
        case pathogenId = "pathogen_id"
        case terminalState = "terminal_state"
        case verdicts
        case authorizedForEmission = "authorized_for_emission"
    }
}

/// Proposed emission the substrate is being asked to authorize.
public struct EmissionProposal: Sendable {
    public let pathogenId: String
    public let carrierFrequencyHz: Double
    public let modulatorFrequencyHz: Double
    public let deliveredPowerDensityWPerCm2: Double
    /// IEEE C95.1-2019 occupational reference level for time-averaged RF power
    /// density. ~10 mW/cm\u{00b2} (= 0.01 W/cm\u{00b2}) at 2-300 GHz for the
    /// occupational/controlled category. INV6 FIRST gate: the requested
    /// emission must be strictly below this. Source: IEEE C95.1-2019 Table 9
    /// (Exposure Reference Levels, occupational).
    public let ieeeC95OccupationalMpeWPerCm2: Double
    /// Independent absolute thermal-damage upper bound. Not a regulatory
    /// limit. At this density short CW exposure drives frank tissue burn.
    /// INV6 SECOND gate: if the MPE check is ever bypassed or mis-configured,
    /// this is the substrate's hard ceiling.
    public let thermalDamageUpperBoundWPerCm2: Double
    public let resonanceTolerancePct: Double

    public init(
        pathogenId: String,
        carrierFrequencyHz: Double,
        modulatorFrequencyHz: Double,
        deliveredPowerDensityWPerCm2: Double,
        ieeeC95OccupationalMpeWPerCm2: Double = 0.01,   // IEEE C95.1-2019 occupational
        thermalDamageUpperBoundWPerCm2: Double = 10.0,  // absolute thermal-burn envelope
        resonanceTolerancePct: Double = 0.5
    ) {
        self.pathogenId = pathogenId
        self.carrierFrequencyHz = carrierFrequencyHz
        self.modulatorFrequencyHz = modulatorFrequencyHz
        self.deliveredPowerDensityWPerCm2 = deliveredPowerDensityWPerCm2
        self.ieeeC95OccupationalMpeWPerCm2 = ieeeC95OccupationalMpeWPerCm2
        self.thermalDamageUpperBoundWPerCm2 = thermalDamageUpperBoundWPerCm2
        self.resonanceTolerancePct = resonanceTolerancePct
    }
}

/// Rife Invariant Engine. Applies the three Rife invariants and the
/// M-tag hard-refuse rule. Any failure yields a REFUSED terminal state.
public struct RifeInvariantEngine {

    // Planck constant in eV\u00b7s (for photon energy check).
    private static let hEvS: Double = 4.135667696e-15

    /// INV1: Cantilever Resonance Lock.
    /// f_delivered must equal (1/2\u{03c0})\u{221a}(k/m) within tolerance.
    public static func cantileverResonanceLock(
        pathogen: PathogenRecord,
        deliveredFrequencyHz: Double,
        tolerancePct: Double
    ) -> RifeVerdict {
        let computed = MORCompute.computeMorHz(
            stiffnessNPerM: pathogen.target.stiffnessNPerM,
            massKg: pathogen.target.massKg
        )
        let declaredDelta = abs(pathogen.computedMorHz - computed) / max(computed, 1.0)
        guard declaredDelta <= 1e-3 else {
            return RifeVerdict(
                invariantId: "GFTCL-RIFE-INV1-CANTILEVER-RESONANCE",
                terminalState: .refused,
                message: "Record's computed_mor_hz inconsistent with k,m. Recompute required.",
                evidence: [
                    "record_mor_hz": String(pathogen.computedMorHz),
                    "substrate_mor_hz": String(computed),
                    "delta_fraction": String(declaredDelta)
                ]
            )
        }

        let delta = abs(deliveredFrequencyHz - computed) / max(computed, 1.0)
        let pass = delta <= (tolerancePct / 100.0)
        return RifeVerdict(
            invariantId: "GFTCL-RIFE-INV1-CANTILEVER-RESONANCE",
            terminalState: pass ? .cure : .refused,
            message: pass
                ? "Emission frequency locked to cantilever resonance within tolerance."
                : "Emission frequency diverges from f=(1/2\u{03c0})\u{221a}(k/m). Substrate REFUSES.",
            evidence: [
                "delivered_hz": String(deliveredFrequencyHz),
                "computed_mor_hz": String(computed),
                "delta_pct": String(delta * 100.0),
                "tolerance_pct": String(tolerancePct)
            ]
        )
    }

    /// INV2: Calm Energy Boundary.
    /// Three-gate check: IEEE C95.1 occupational MPE (primary), thermal-damage
    /// upper bound (backstop), and non-ionizing photon energy.
    public static func calmEnergyBoundary(
        deliveredPowerDensityWPerCm2 p: Double,
        ieeeC95OccupationalMpeWPerCm2 pIeee: Double,
        thermalDamageUpperBoundWPerCm2 pThermal: Double,
        emissionFrequencyHz f: Double
    ) -> RifeVerdict {
        let photonEv = hEvS * f
        let ieeeOk = p < pIeee
        let thermalOk = p < pThermal
        let photonOk = photonEv < 10.0 // ionizing threshold ~10 eV
        let pass = ieeeOk && thermalOk && photonOk
        var msg = ""
        if !ieeeOk {
            msg = "Delivered \(p) W/cm\u{00b2} exceeds IEEE C95.1-2019 occupational reference level (\(pIeee) W/cm\u{00b2}). Substrate REFUSES."
        } else if !thermalOk {
            msg = "Delivered \(p) W/cm\u{00b2} exceeds thermal-damage upper bound (\(pThermal) W/cm\u{00b2}). Substrate REFUSES."
        } else if !photonOk {
            msg = "Photon energy \(photonEv) eV \u{2265} 10 eV (ionizing). Rife protocol is non-ionizing only. Substrate REFUSES."
        } else {
            msg = "Calm energy bounds satisfied: below IEEE C95.1 occupational MPE, below thermal ceiling, non-ionizing."
        }
        return RifeVerdict(
            invariantId: "GFTCL-RIFE-INV2-CALM-ENERGY-BOUNDARY",
            terminalState: pass ? .cure : .refused,
            message: msg,
            evidence: [
                "delivered_w_per_cm2": String(p),
                "ieee_c95_occupational_mpe_w_per_cm2": String(pIeee),
                "thermal_damage_upper_bound_w_per_cm2": String(pThermal),
                "photon_energy_ev": String(photonEv),
                "ieee_ok": String(ieeeOk),
                "thermal_ok": String(thermalOk),
                "photon_ok": String(photonOk)
            ]
        )
    }

    /// INV3: Harmonic Sideband (M.O.P.A.) Integrity.
    /// Carrier must be within band; carrier\u{00b1}modulator must resolve to MOR; record must be M-tagged.
    public static func mopaHarmonicSideband(
        pathogen: PathogenRecord,
        carrierHz: Double,
        modulatorHz: Double,
        tolerancePct: Double
    ) -> RifeVerdict {
        let band = pathogen.mopaBand
        let carrierOk = carrierHz >= band.carrierLowHz && carrierHz <= band.carrierHighHz
        let modulatorOk = modulatorHz >= band.modulatorLowHz && modulatorHz <= band.modulatorHighHz
        let upperSideband = carrierHz + modulatorHz
        let lowerSideband = carrierHz - modulatorHz
        let target = pathogen.computedMorHz
        let upperDelta = abs(upperSideband - target) / max(target, 1.0)
        let lowerDelta = abs(lowerSideband - target) / max(target, 1.0)
        let bestDelta = min(upperDelta, lowerDelta)
        let sidebandOk = bestDelta <= (tolerancePct / 100.0)
        let mTagOk = pathogen.epistemicTag == .measured

        let pass = carrierOk && modulatorOk && sidebandOk && mTagOk
        var msg = ""
        if !mTagOk {
            msg = "Pathogen record is epistemic_tag='\(pathogen.epistemicTag.rawValue)'. Only 'M' (Measured) authorizes emission. REFUSED."
        } else if !carrierOk {
            msg = "Carrier \(carrierHz) Hz outside MOPA band [\(band.carrierLowHz),\(band.carrierHighHz)]."
        } else if !modulatorOk {
            msg = "Modulator \(modulatorHz) Hz outside audio band."
        } else if !sidebandOk {
            msg = "carrier\u{00b1}modulator does not resolve to MOR target within tolerance."
        } else {
            msg = "MOPA sideband resolves to measured MOR. Emission authorized."
        }
        return RifeVerdict(
            invariantId: "GFTCL-RIFE-INV3-MOPA-HARMONIC-SIDEBAND",
            terminalState: pass ? .cure : .refused,
            message: msg,
            evidence: [
                "carrier_hz": String(carrierHz),
                "modulator_hz": String(modulatorHz),
                "upper_sideband_hz": String(upperSideband),
                "lower_sideband_hz": String(lowerSideband),
                "target_mor_hz": String(target),
                "best_delta_pct": String(bestDelta * 100.0),
                "epistemic_tag": pathogen.epistemicTag.rawValue
            ]
        )
    }

    /// Full suite. All three invariants MUST pass for emission to be authorized.
    public static func evaluate(
        pathogen: PathogenRecord,
        proposal: EmissionProposal
    ) -> RifeSuiteVerdict {
        // Derive the emission frequency from the carrier+modulator pair.
        // We choose whichever sideband (upper or lower) is closer to the MOR.
        let upper = proposal.carrierFrequencyHz + proposal.modulatorFrequencyHz
        let lower = proposal.carrierFrequencyHz - proposal.modulatorFrequencyHz
        let deliveredHz = abs(upper - pathogen.computedMorHz) < abs(lower - pathogen.computedMorHz) ? upper : lower

        let v1 = cantileverResonanceLock(
            pathogen: pathogen,
            deliveredFrequencyHz: deliveredHz,
            tolerancePct: proposal.resonanceTolerancePct
        )
        let v2 = calmEnergyBoundary(
            deliveredPowerDensityWPerCm2: proposal.deliveredPowerDensityWPerCm2,
            ieeeC95OccupationalMpeWPerCm2: proposal.ieeeC95OccupationalMpeWPerCm2,
            thermalDamageUpperBoundWPerCm2: proposal.thermalDamageUpperBoundWPerCm2,
            emissionFrequencyHz: deliveredHz
        )
        let v3 = mopaHarmonicSideband(
            pathogen: pathogen,
            carrierHz: proposal.carrierFrequencyHz,
            modulatorHz: proposal.modulatorFrequencyHz,
            tolerancePct: proposal.resonanceTolerancePct
        )

        let verdicts = [v1, v2, v3]
        let allCure = verdicts.allSatisfy { $0.terminalState == .cure }
        return RifeSuiteVerdict(
            pathogenId: pathogen.pathogenId,
            terminalState: allCure ? .cure : .refused,
            verdicts: verdicts,
            authorizedForEmission: allCure
        )
    }
}
