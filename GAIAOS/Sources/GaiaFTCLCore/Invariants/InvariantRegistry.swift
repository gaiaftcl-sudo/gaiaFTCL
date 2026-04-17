import Foundation

public actor InvariantRegistry {
    public static let shared = InvariantRegistry()
    
    private var invariants: [String: InvariantRecord] = [:]
    private let registryUrl: URL
    
    private init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        self.registryUrl = home.appendingPathComponent(".gaiaftcl/invariants")
        try? FileManager.default.createDirectory(at: registryUrl, withIntermediateDirectories: true)
    }
    
    public func loadAll() {
        invariants.removeAll()
        guard let enumerator = FileManager.default.enumerator(at: registryUrl, includingPropertiesForKeys: nil) else { return }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "json" {
                if let data = try? Data(contentsOf: fileURL),
                   let record = try? JSONDecoder().decode(InvariantRecord.self, from: data) {
                    invariants[record.invariantId] = record
                }
            }
        }
        
        // Load seeds if not present
        let seedNames = [
            "OWL-NEURO-INV1-CONSTITUTIVE",
            "OWL-NEURO-INV2-ESCAPEE",
            "OWL-NEURO-INV3-STEROID",
            "OWL-NEURO-CONST-001-FETAL-CLOSURE",
            "GFTCL-OWL-INV-001",
            "GFTCL-PINEAL-001",
            "GFTCL-RIFE-INV1-CANTILEVER-RESONANCE",
            "GFTCL-RIFE-INV2-CALM-ENERGY-BOUNDARY",
            "GFTCL-RIFE-INV3-MOPA-HARMONIC-SIDEBAND"
        ]
        
        for name in seedNames {
            if invariants[name] == nil {
                if let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "InvariantSeeds"),
                   let data = try? Data(contentsOf: url),
                   let record = try? JSONDecoder().decode(InvariantRecord.self, from: data) {
                    try? save(record)
                }
            }
        }
    }
    
    public func get(id: String) -> InvariantRecord? {
        return invariants[id]
    }
    
    public func list() -> [InvariantRecord] {
        return Array(invariants.values)
    }
    
    public func save(_ record: InvariantRecord) throws {
        let url = registryUrl.appendingPathComponent("\(record.invariantId).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(record)
        try data.write(to: url)
        invariants[record.invariantId] = record
        
        // Also write to evidence/invariants/<id>/record.json
        let evidenceDir = URL(fileURLWithPath: "evidence/invariants/\(record.invariantId)")
        try? FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
        let evidenceUrl = evidenceDir.appendingPathComponent("record.json")
        try? data.write(to: evidenceUrl)
    }
    
    public func seed(record: InvariantRecord) throws {
        if invariants[record.invariantId] == nil {
            try save(record)
        }
    }
    
    public func transitionStatus(id: String, to newStatus: String, evidence: String? = nil) throws {
        guard var record = invariants[id] else { throw NSError(domain: "InvariantNotFound", code: 404) }
        
        let oldStatus = record.status
        if newStatus == "CURE-CLOSED" {
            guard oldStatus == "CURE-PROXY" else {
                throw NSError(domain: "InvalidTransition", code: 400)
            }
            guard let ev = evidence, !ev.isEmpty else {
                throw NSError(domain: "MissingEvidence", code: 400)
            }
        }
        
        // Transition logic
        record.status = newStatus
        
        var history = record.history ?? []
        history.append(HistoryEvent(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            event: "transition_to_\(newStatus)",
            actorWalletHash: "sha256:operator" // placeholder
        ))
        record.history = history
        
        try save(record)
    }
}
