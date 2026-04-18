import Foundation

/// Epistemic tag per UUM-8D OWL Protocol.
/// - M: Measured (AFM/cryo-EM/peer-reviewed empirical)
/// - T: Theoretical (derived from model; not yet measured)
/// - C: Computed (derived from measured inputs)
/// - A: Assumed (placeholder; MUST be refused for emission authorization)
/// - R: Refused
public enum EpistemicTag: String, Codable, Sendable {
    case measured = "M"
    case theoretical = "T"
    case computed = "C"
    case assumed = "A"
    case refused = "R"
}

/// Terminal states per GFTCL-URS-001 contract.
public enum TerminalState: String, Codable, Sendable {
    case calorie = "CALORIE"
    case cure = "CURE"
    case refused = "REFUSED"
}

/// Structural target of a pathogen.
/// Models viral spikes, bacterial cell walls, fungal cell walls, etc.
/// as cantilever beams fixed at one end to the pathogen body.
public struct StructuralTarget: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case viralSpike = "viral_spike"
        case viralCapsid = "viral_capsid"
        case viralEnvelope = "viral_envelope"
        case bacterialCellWall = "bacterial_cell_wall"
        case bacterialFlagellum = "bacterial_flagellum"
        case fungalCellWall = "fungal_cell_wall"
        case protozoalMembrane = "protozoal_membrane"
        case prionFibril = "prion_fibril"
    }

    public var kind: Kind
    /// Effective stiffness k in N/m (from AFM nanoindentation or molecular dynamics).
    public var stiffnessNPerM: Double
    /// Effective mass m in kg (from cryo-EM / mass spec / sequence-derived MW).
    public var massKg: Double
    /// Characteristic length in metres (optional, for full beam theory).
    public var lengthM: Double?
    /// Young's modulus in Pa (optional; if supplied, substrate can cross-check with k).
    public var youngsModulusPa: Double?

    public init(kind: Kind, stiffnessNPerM: Double, massKg: Double, lengthM: Double? = nil, youngsModulusPa: Double? = nil) {
        self.kind = kind
        self.stiffnessNPerM = stiffnessNPerM
        self.massKg = massKg
        self.lengthM = lengthM
        self.youngsModulusPa = youngsModulusPa
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case stiffnessNPerM = "stiffness_n_per_m"
        case massKg = "mass_kg"
        case lengthM = "length_m"
        case youngsModulusPa = "youngs_modulus_pa"
    }
}

/// Carrier band required by the MOPA invariant.
public struct MOPABand: Codable, Sendable {
    public var carrierLowHz: Double
    public var carrierHighHz: Double
    public var modulatorLowHz: Double
    public var modulatorHighHz: Double

    /// Default Rife Ray #5 band: 3.0-4.0 MHz carrier, 20 Hz - 20 kHz audio modulator.
    public static let rifeDefault = MOPABand(
        carrierLowHz: 3.0e6,
        carrierHighHz: 4.0e6,
        modulatorLowHz: 20.0,
        modulatorHighHz: 20_000.0
    )

    public init(carrierLowHz: Double, carrierHighHz: Double, modulatorLowHz: Double, modulatorHighHz: Double) {
        self.carrierLowHz = carrierLowHz
        self.carrierHighHz = carrierHighHz
        self.modulatorLowHz = modulatorLowHz
        self.modulatorHighHz = modulatorHighHz
    }

    enum CodingKeys: String, CodingKey {
        case carrierLowHz = "carrier_low_hz"
        case carrierHighHz = "carrier_high_hz"
        case modulatorLowHz = "modulator_low_hz"
        case modulatorHighHz = "modulator_high_hz"
    }
}

/// Pathogen record. Each record is a proof-carrying artefact for the OWL
/// Protocol: the computed MOR is entangled with its structural parameters
/// and its epistemic tag. A record with tag != .measured CANNOT authorize
/// any emission; the substrate will REFUSE.
public struct PathogenRecord: Codable, Sendable {
    public var schemaVersion: String = "1.0"
    public var pathogenId: String
    public var commonName: String
    public var scientificName: String
    public var taxonomy: Taxonomy
    public var target: StructuralTarget
    /// Computed Mortal Oscillatory Rate in Hz. Must equal (1/2\u{03c0})\u{221a}(k/m).
    public var computedMorHz: Double
    public var mopaBand: MOPABand
    public var epistemicTag: EpistemicTag
    public var status: String
    public var description: String
    public var invariantsApplied: [String]
    public var literature: [Literature]?
    public var provenance: Provenance?
    public var history: [HistoryEvent]?

    public init(
        schemaVersion: String = "1.0",
        pathogenId: String,
        commonName: String,
        scientificName: String,
        taxonomy: Taxonomy,
        target: StructuralTarget,
        computedMorHz: Double,
        mopaBand: MOPABand = .rifeDefault,
        epistemicTag: EpistemicTag,
        status: String = "DRAFT",
        description: String = "",
        invariantsApplied: [String] = [
            "GFTCL-RIFE-INV1-CANTILEVER-RESONANCE",
            "GFTCL-RIFE-INV2-CALM-ENERGY-BOUNDARY",
            "GFTCL-RIFE-INV3-MOPA-HARMONIC-SIDEBAND"
        ],
        literature: [Literature]? = nil,
        provenance: Provenance? = nil,
        history: [HistoryEvent]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.pathogenId = pathogenId
        self.commonName = commonName
        self.scientificName = scientificName
        self.taxonomy = taxonomy
        self.target = target
        self.computedMorHz = computedMorHz
        self.mopaBand = mopaBand
        self.epistemicTag = epistemicTag
        self.status = status
        self.description = description
        self.invariantsApplied = invariantsApplied
        self.literature = literature
        self.provenance = provenance
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case pathogenId = "pathogen_id"
        case commonName = "common_name"
        case scientificName = "scientific_name"
        case taxonomy
        case target
        case computedMorHz = "computed_mor_hz"
        case mopaBand = "mopa_band"
        case epistemicTag = "epistemic_tag"
        case status
        case description
        case invariantsApplied = "invariants_applied"
        case literature
        case provenance
        case history
    }
}

public struct Taxonomy: Codable, Sendable {
    public var kingdom: String
    public var phylum: String?
    public var genus: String?
    public var species: String?

    public init(kingdom: String, phylum: String? = nil, genus: String? = nil, species: String? = nil) {
        self.kingdom = kingdom
        self.phylum = phylum
        self.genus = genus
        self.species = species
    }
}

/// MOR computation. Single source of truth for f = (1/2\u{03c0})\u{221a}(k/m).
public struct MORCompute {
    public static func computeMorHz(stiffnessNPerM k: Double, massKg m: Double) -> Double {
        precondition(k > 0 && m > 0, "k and m must be positive")
        return (1.0 / (2.0 * .pi)) * (k / m).squareRoot()
    }
}
