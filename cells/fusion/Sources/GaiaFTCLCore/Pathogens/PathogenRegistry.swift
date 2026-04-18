import Foundation

/// Actor that manages pathogen records on disk and enforces the OWL
/// Protocol invariants. Seeds ship in the GaiaFTCLCore bundle under
/// Pathogens/Seeds/. Operator-added records land in ~/.gaiaftcl/pathogens/.
public actor PathogenRegistry {
    public static let shared = PathogenRegistry()

    private var pathogens: [String: PathogenRecord] = [:]
    private let registryUrl: URL

    private init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        self.registryUrl = home.appendingPathComponent(".gaiaftcl/pathogens")
        try? FileManager.default.createDirectory(at: registryUrl, withIntermediateDirectories: true)
    }

    public func loadAll() {
        pathogens.removeAll()

        // Operator-edited records take precedence.
        if let enumerator = FileManager.default.enumerator(at: registryUrl, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "json" {
                if let data = try? Data(contentsOf: fileURL),
                   let record = try? JSONDecoder().decode(PathogenRecord.self, from: data) {
                    pathogens[record.pathogenId] = record
                }
            }
        }

        // Seeds from the bundle. Keep any operator overrides already loaded.
        let seedNames = [
            "P-SARS-COV-2",
            "P-INFLUENZA-A-H1N1",
            "P-HIV-1",
            "P-HSV-1",
            "P-HBV",
            "P-EBOLA-ZAIRE",
            "P-RSV-A",
            "P-MTB-H37RV",
            "P-SAUREUS-USA300",
            "P-ECOLI-K12",
            "P-CANDIDA-ALBICANS",
            "P-RIFE-BX-HISTORICAL"
        ]
        for name in seedNames where pathogens[name] == nil {
            if let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "PathogenSeeds"),
               let data = try? Data(contentsOf: url),
               let record = try? JSONDecoder().decode(PathogenRecord.self, from: data) {
                try? save(record)
            }
        }
    }

    public func get(id: String) -> PathogenRecord? {
        return pathogens[id]
    }

    public func list() -> [PathogenRecord] {
        return Array(pathogens.values).sorted { $0.pathogenId < $1.pathogenId }
    }

    public func save(_ record: PathogenRecord) throws {
        // Substrate constraint: computed_mor_hz must equal f=(1/2\u{03c0})\u{221a}(k/m).
        let expected = MORCompute.computeMorHz(
            stiffnessNPerM: record.target.stiffnessNPerM,
            massKg: record.target.massKg
        )
        let delta = abs(record.computedMorHz - expected) / max(expected, 1.0)
        guard delta <= 1e-3 else {
            throw NSError(
                domain: "PathogenRegistry",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "computed_mor_hz inconsistent with f=(1/2\u{03c0})\u{221a}(k/m). expected=\(expected), got=\(record.computedMorHz)"]
            )
        }

        let url = registryUrl.appendingPathComponent("\(record.pathogenId).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: url)
        pathogens[record.pathogenId] = record

        // Mirror to evidence/pathogens/<id>/record.json.
        let evidenceDir = URL(fileURLWithPath: "evidence/pathogens/\(record.pathogenId)")
        try? FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
        try? data.write(to: evidenceDir.appendingPathComponent("record.json"))
    }

    /// Convenience factory: build a record from inputs and compute MOR.
    public func create(
        pathogenId: String,
        commonName: String,
        scientificName: String,
        taxonomy: Taxonomy,
        target: StructuralTarget,
        epistemicTag: EpistemicTag,
        description: String = "",
        literature: [Literature]? = nil
    ) throws -> PathogenRecord {
        let mor = MORCompute.computeMorHz(stiffnessNPerM: target.stiffnessNPerM, massKg: target.massKg)
        let record = PathogenRecord(
            pathogenId: pathogenId,
            commonName: commonName,
            scientificName: scientificName,
            taxonomy: taxonomy,
            target: target,
            computedMorHz: mor,
            epistemicTag: epistemicTag,
            status: epistemicTag == .measured ? "CURE-PROXY" : "DRAFT",
            description: description,
            literature: literature
        )
        try save(record)
        return record
    }

    /// Evaluate an emission proposal against the Rife invariant suite.
    public func evaluateProposal(_ proposal: EmissionProposal) throws -> RifeSuiteVerdict {
        guard let pathogen = pathogens[proposal.pathogenId] else {
            throw NSError(domain: "PathogenRegistry", code: 404, userInfo: [NSLocalizedDescriptionKey: "Pathogen not found: \(proposal.pathogenId)"])
        }
        return RifeInvariantEngine.evaluate(pathogen: pathogen, proposal: proposal)
    }

    /// Refuse a pathogen record. Sets status=REFUSED and epistemic_tag=R.
    public func refuse(id: String, reason: String) throws {
        guard var record = pathogens[id] else {
            throw NSError(domain: "PathogenRegistry", code: 404)
        }
        record.status = "REFUSED"
        record.epistemicTag = .refused
        var history = record.history ?? []
        history.append(HistoryEvent(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            event: "refused:\(reason)",
            actorWalletHash: "sha256:operator"
        ))
        record.history = history
        try save(record)
    }
}
