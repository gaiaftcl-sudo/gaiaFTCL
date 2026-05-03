import Foundation

/// Pure Swift fusion constitutional substrate — replaces the legacy WebAssembly module.
/// **M⁸ = S⁴ × C⁴**: constitutional **`checkConstitutional`** consumes per-prim **S⁴** tensor rows (via **`ConstitutionalInputs`**) and emits **C⁴** scalars plus violation / terminal classification — not legacy envelope counts or a triple-product residual masquerading as manifold closure.
public struct SubstrateEngine: Sendable {

    public init() {}

    // MARK: — Primary API (vQbit VM / mmap S⁴ row)

    public func checkConstitutional(_ inputs: ConstitutionalInputs) -> ConstitutionalOutputs {
        guard inputs.isStructurallyValid else {
            return ConstitutionalOutputs.blocked(reason: "structurally invalid inputs")
        }
        var code: UInt8 = 0
        if inputs.plasmaPressure < inputs.minPlasmaPressure { code |= 0x01 }
        if inputs.fieldStrength < inputs.minFieldStrength { code |= 0x02 }
        if inputs.s3_spatial < 0.2 { code |= 0x04 }
        if inputs.s1_structural < 0.4 { code |= 0x08 }

        let terminalState = terminalFromViolation(code, inputs: inputs)
        return ConstitutionalOutputs(
            violationCode: code,
            terminalState: terminalState,
            c1_trust: Self.clamp(inputs.s1_structural),
            c2_identity: Self.clamp(inputs.s2_temporal),
            c3_closure: Self.clamp(inputs.s3_spatial),
            c4_consequence: Self.clamp(inputs.s4_observable),
            computedAt: Date()
        )
    }

    private func terminalFromViolation(_ code: UInt8, inputs: ConstitutionalInputs) -> TerminalState {
        if code >= 4 { return .blocked }
        if code > 0 { return .refused }
        let health = (inputs.s1_structural + inputs.s3_spatial) / 2.0
        if health >= 0.8 { return .calorie }
        return .cure
    }

    private static func clamp(_ x: Double) -> Double {
        min(max(x, 0), 1)
    }

    // MARK: — Legacy PQ triple (Fusion telemetry → manifold proxies)

    /// Converts plasma telemetry (`i_p`, `b_t`, `n_e`) into **[0, 1]** S⁴ proxies and runs the same constitutional geometry as the VM path.
    public func checkConstitutional(i_p: Double, b_t: Double, n_e: Double, plantKind: UInt32 = 0) -> FusionConstitutionalSnapshot {
        let out = checkConstitutional(Self.legacyTripleToInputs(i_p: i_p, b_t: b_t, n_e: n_e, plantKind: plantKind))
        return FusionConstitutionalSnapshot(
            violationCode: out.violationCode,
            terminalState: out.fusionLegacyTerminalUInt8,
            closureResidual: out.c3_closure,
            computedAt: out.computedAt
        )
    }

    private static func legacyTripleToInputs(i_p: Double, b_t: Double, n_e: Double, plantKind: UInt32) -> ConstitutionalInputs {
        let stressIp = min(max(i_p / 20.0e6, 0), 1)
        let stressBt = min(max(b_t / 15.0, 0), 1)
        let stressNe = min(max(n_e / 5.0e20, 0), 1)
        let s1 = 1.0 - stressIp
        let s2 = 1.0 - stressBt
        let s3 = 1.0 - stressNe
        let s4 = (s1 + s2 + s3) / 3.0
        return ConstitutionalInputs(
            s1_structural: s1,
            s2_temporal: s2,
            s3_spatial: s3,
            s4_observable: s4,
            plasmaPressure: s1,
            fieldStrength: s3,
            minPlasmaPressure: 0.3,
            minFieldStrength: 0.3,
            plantKind: UInt8(truncatingIfNeeded: plantKind)
        )
    }

    /// PQ-UI-008 constitutional violation bands (0 = PASS, 1–6 = C-001…C-006) — **legacy triple** physics bands for FusionBridge diagnostics only.
    public func constitutionalViolationCode(i_p: Double, b_t: Double, n_e: Double) -> UInt8 {
        if i_p.isNaN || b_t.isNaN || n_e.isNaN { return 4 }
        if i_p < 0 || b_t < 0 || n_e < 0 { return 5 }
        if i_p > 20.0e6 { return 1 }
        if b_t > 15.0 { return 2 }
        if n_e > 5.0e20 { return 3 }
        let stress = (i_p / 20.0e6) + (b_t / 15.0) + (n_e / 5.0e20)
        if stress > 2.5 { return 6 }
        return 0
    }

    /// PQ-UI-005 terminal classification (0 CALORIE, 1 CURE, 2 REFUSED) — retained for **`FusionConstitutionalSnapshot`** consumers that still expect **`UInt8`** rail indices.
    public func terminalStateUInt8(entropy: Double, truth: Double, plantKind: UInt32) -> UInt8 {
        let _ = plantKind
        if entropy < 0.3 && truth > 0.7 { return 0 }
        if entropy < 0.6 && truth > 0.5 { return 1 }
        return 2
    }
}

// MARK: — Inputs / outputs

public struct ConstitutionalInputs: Sendable {
    public let s1_structural: Double
    public let s2_temporal: Double
    public let s3_spatial: Double
    public let s4_observable: Double
    public let plasmaPressure: Double
    public let fieldStrength: Double
    public let minPlasmaPressure: Double
    public let minFieldStrength: Double
    public let plantKind: UInt8

    public init(
        s1_structural: Double,
        s2_temporal: Double,
        s3_spatial: Double,
        s4_observable: Double,
        plasmaPressure: Double,
        fieldStrength: Double,
        minPlasmaPressure: Double,
        minFieldStrength: Double,
        plantKind: UInt8
    ) {
        self.s1_structural = s1_structural
        self.s2_temporal = s2_temporal
        self.s3_spatial = s3_spatial
        self.s4_observable = s4_observable
        self.plasmaPressure = plasmaPressure
        self.fieldStrength = fieldStrength
        self.minPlasmaPressure = minPlasmaPressure
        self.minFieldStrength = minFieldStrength
        self.plantKind = plantKind
    }

    public var isStructurallyValid: Bool {
        !s1_structural.isNaN && !s2_temporal.isNaN &&
            !s3_spatial.isNaN && !s4_observable.isNaN &&
            !plasmaPressure.isNaN && !fieldStrength.isNaN
    }
}

public struct ConstitutionalOutputs: Sendable {
    public let violationCode: UInt8
    public let terminalState: TerminalState
    public let c1_trust: Double
    public let c2_identity: Double
    public let c3_closure: Double
    public let c4_consequence: Double
    public let computedAt: Date

    public init(
        violationCode: UInt8,
        terminalState: TerminalState,
        c1_trust: Double,
        c2_identity: Double,
        c3_closure: Double,
        c4_consequence: Double,
        computedAt: Date
    ) {
        self.violationCode = violationCode
        self.terminalState = terminalState
        self.c1_trust = c1_trust
        self.c2_identity = c2_identity
        self.c3_closure = c3_closure
        self.c4_consequence = c4_consequence
        self.computedAt = computedAt
    }

    public static func blocked(reason: String) -> ConstitutionalOutputs {
        let _ = reason
        return ConstitutionalOutputs(
            violationCode: 0xFF,
            terminalState: .blocked,
            c1_trust: 0,
            c2_identity: 0,
            c3_closure: 0,
            c4_consequence: 0,
            computedAt: Date()
        )
    }

    /// **`CompositeLayoutManager`** historically consumed **`FusionConstitutionalSnapshot.terminalState`** as **`UInt8`** **0 / 1 / 2**.
    public var fusionLegacyTerminalUInt8: UInt8 {
        switch terminalState {
        case .calorie: return 0
        case .cure: return 1
        case .refused: return 2
        case .blocked: return 2
        }
    }
}

/// Outputs consumed by **`CompositeLayoutManager.updateFromSubstrate`** / FusionBridge (legacy triple path).
public struct FusionConstitutionalSnapshot: Sendable {
    public let violationCode: UInt8
    public let terminalState: UInt8
    /// Legacy field name — holds **`c3_closure`** from **`ConstitutionalOutputs`** (manifold connectivity stress), not PQ envelope ratios.
    public let closureResidual: Double
    public let computedAt: Date

    public init(violationCode: UInt8, terminalState: UInt8, closureResidual: Double, computedAt: Date) {
        self.violationCode = violationCode
        self.terminalState = terminalState
        self.closureResidual = closureResidual
        self.computedAt = computedAt
    }
}
