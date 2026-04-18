import Foundation

public struct InvariantRecord: Codable, Sendable {
    public var schemaVersion: String = "1.0"
    public var invariantId: String
    public var title: String
    public var domain: String
    public var owlClassification: String
    public var epistemicTag: String
    public var status: String
    public var description: String
    public var measurementVectors: [MeasurementVector]?
    public var linkedInvariants: [String]?
    public var closureConditionId: String?
    public var literature: [Literature]?
    public var testHarness: TestHarness?
    public var provenance: Provenance?
    public var history: [HistoryEvent]?
    
    public init(schemaVersion: String = "1.0", invariantId: String, title: String, domain: String, owlClassification: String, epistemicTag: String, status: String, description: String, measurementVectors: [MeasurementVector]? = nil, linkedInvariants: [String]? = nil, closureConditionId: String? = nil, literature: [Literature]? = nil, testHarness: TestHarness? = nil, provenance: Provenance? = nil, history: [HistoryEvent]? = nil) {
        self.schemaVersion = schemaVersion
        self.invariantId = invariantId
        self.title = title
        self.domain = domain
        self.owlClassification = owlClassification
        self.epistemicTag = epistemicTag
        self.status = status
        self.description = description
        self.measurementVectors = measurementVectors
        self.linkedInvariants = linkedInvariants
        self.closureConditionId = closureConditionId
        self.literature = literature
        self.testHarness = testHarness
        self.provenance = provenance
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case invariantId = "invariant_id"
        case title
        case domain
        case owlClassification = "owl_classification"
        case epistemicTag = "epistemic_tag"
        case status
        case description
        case measurementVectors = "measurement_vectors"
        case linkedInvariants = "linked_invariants"
        case closureConditionId = "closure_condition_id"
        case literature
        case testHarness = "test_harness"
        case provenance
        case history
    }
}

public struct MeasurementVector: Codable, Sendable {
    public var vectorId: String
    public var label: String
    public var count: Int
    public var source: String
    
    public init(vectorId: String, label: String, count: Int, source: String) {
        self.vectorId = vectorId
        self.label = label
        self.count = count
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case vectorId = "vector_id"
        case label, count, source
    }
}

public struct Literature: Codable, Sendable {
    public var pmidOrDoi: String
    public var year: Int
    public var role: String
    
    public init(pmidOrDoi: String, year: Int, role: String) {
        self.pmidOrDoi = pmidOrDoi
        self.year = year
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case pmidOrDoi = "pmid_or_doi"
        case year, role
    }
}

public struct TestHarness: Codable, Sendable {
    public var type: String
    public var harnessId: String
    public var inputs: [String]
    public var passCriteria: String
    public var implementation: String
    
    public init(type: String, harnessId: String, inputs: [String], passCriteria: String, implementation: String) {
        self.type = type
        self.harnessId = harnessId
        self.inputs = inputs
        self.passCriteria = passCriteria
        self.implementation = implementation
    }

    enum CodingKeys: String, CodingKey {
        case type
        case harnessId = "harness_id"
        case inputs
        case passCriteria = "pass_criteria"
        case implementation
    }
}

public struct Provenance: Codable, Sendable {
    public var createdAt: String
    public var createdByWalletHash: String
    public var cellId: String
    public var signature: String
    
    public init(createdAt: String, createdByWalletHash: String, cellId: String, signature: String) {
        self.createdAt = createdAt
        self.createdByWalletHash = createdByWalletHash
        self.cellId = cellId
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case createdByWalletHash = "created_by_wallet_hash"
        case cellId = "cell_id"
        case signature
    }
}

public struct HistoryEvent: Codable, Sendable {
    public var timestamp: String
    public var event: String
    public var actorWalletHash: String
    
    public init(timestamp: String, event: String, actorWalletHash: String) {
        self.timestamp = timestamp
        self.event = event
        self.actorWalletHash = actorWalletHash
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, event
        case actorWalletHash = "actor_wallet_hash"
    }
}
