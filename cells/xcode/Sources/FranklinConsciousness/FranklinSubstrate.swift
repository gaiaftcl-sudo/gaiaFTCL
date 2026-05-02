import Foundation
import GaiaFTCLCore
import GRDB

/// Owns GRDB writers and wires repositories into `C4MemoryStore` and document persistence.
public actor FranklinSubstrate {
    public static let shared = FranklinSubstrate()

    private var writer: (any DatabaseWriter)?
    private var memoryRepository: FranklinMemoryRepository?

    public func bootstrapProduction() async throws {
        guard writer == nil else { return }
        let pool = try await SubstrateDatabase.shared.pool()
        await attach(pool)
        let iso = ISO8601DateFormatter().string(from: Date())
        try LanguageGameContractSeeder.seedCanonicalContracts(writer: pool, timestampISO: iso)
    }

    public func bootstrapForTests(_ queue: DatabaseQueue) async {
        await attach(queue)
    }

    private func attach(_ w: any DatabaseWriter) async {
        writer = w
        memoryRepository = FranklinMemoryRepository(db: w)
        await C4MemoryStore.shared.setup(memoryRepository: memoryRepository!)
    }

    public func memoryRepositoryForTests() -> FranklinMemoryRepository? {
        memoryRepository
    }

    // MARK: — Document tables

    public func upsertAutonomyEnvelope(snapshotJSON: String, version: Int, timestampISO: String) async {
        guard let w = writer else { return }
        let repo = FranklinDocumentRepository(db: w)
        try? repo.upsertAutonomyEnvelope(snapshotJSON: snapshotJSON, version: version, timestampISO: timestampISO)
    }

    public func insertSelfModelHistory(
        id: String,
        version: Int,
        reason: String,
        profileJSON: String,
        drift: Double,
        narrative: String,
        sha256: String,
        timestampISO: String
    ) async {
        guard let w = writer else { return }
        let repo = FranklinDocumentRepository(db: w)
        try? repo.insertSelfModelHistory(
            id: id,
            version: version,
            reason: reason,
            profileJSON: profileJSON,
            drift: drift,
            narrative: narrative,
            sha256: sha256,
            timestampISO: timestampISO
        )
    }

    public func insertLearningReceipt(
        id: String,
        sessionID: String,
        terminal: String,
        receiptPath: String,
        receiptSha256: String,
        timestampISO: String
    ) async {
        guard let w = writer else { return }
        let repo = FranklinDocumentRepository(db: w)
        try? repo.insertLearningReceipt(
            id: id,
            sessionID: sessionID,
            terminal: terminal,
            receiptPath: receiptPath,
            receiptSha256: receiptSha256,
            timestampISO: timestampISO
        )
    }

    public func insertMetalearningEvent(id: String, payloadJSON: String, timestampISO: String) async {
        guard let w = writer else { return }
        let repo = FranklinDocumentRepository(db: w)
        try? repo.insertMetalearningEvent(id: id, payloadJSON: payloadJSON, timestampISO: timestampISO)
    }

    public func insertGenesisLearningReceiptIfAbsent(
        id: String,
        sessionID: String,
        terminal: String,
        receiptPath: String,
        receiptSha256: String,
        timestampISO: String,
        kind: String,
        payloadJSON: String,
        canonicalSha256: String
    ) async {
        guard let w = writer else { return }
        let repo = FranklinDocumentRepository(db: w)
        try? repo.insertGenesisLearningReceiptIfAbsent(
            id: id,
            sessionID: sessionID,
            terminal: terminal,
            receiptPath: receiptPath,
            receiptSha256: receiptSha256,
            timestampISO: timestampISO,
            kind: kind,
            payloadJSON: payloadJSON,
            canonicalSha256: canonicalSha256
        )
    }

    public func insertSelfModelGenesisIfAbsent(
        id: String,
        version: Int,
        reason: String,
        profileJSON: String,
        drift: Double,
        narrative: String,
        sha256: String,
        timestampISO: String
    ) async {
        guard let w = writer else { return }
        let repo = FranklinDocumentRepository(db: w)
        try? repo.insertSelfModelGenesisIfAbsent(
            id: id,
            version: version,
            reason: reason,
            profileJSON: profileJSON,
            drift: drift,
            narrative: narrative,
            sha256: sha256,
            timestampISO: timestampISO
        )
    }

    /// Sovereign M⁸ language-game contracts (**FUSION-001**, **HEALTH-001**) — insert-or-ignore (idempotent).
    public func seedLanguageGameContracts(timestampISO: String) async {
        guard let w = writer else { return }
        try? LanguageGameContractSeeder.seedCanonicalContracts(writer: w, timestampISO: timestampISO)
    }

    public func recordHealingEvent(primID: UUID, reason: UInt8, violationCode: UInt8, outcome: String?) async throws {
        guard let w = writer else { return }
        let repo = FranklinDocumentRepository(db: w)
        let id = UUID().uuidString
        let iso = ISO8601DateFormatter().string(from: Date())
        try repo.insertHealingEvent(
            id: id,
            primID: primID,
            reason: Int(reason),
            violationCode: Int(violationCode),
            healedAtISO: iso,
            outcome: outcome
        )
    }

    public func allLanguageGameContracts() async throws -> [(gameID: String, domain: String?, primPaths: [String])] {
        guard let w = writer else { throw NSError(domain: "FranklinSubstrate", code: 1) }
        let repo = FranklinDocumentRepository(db: w)
        return try repo.fetchLanguageGameContractSurfaces()
    }

    public func genesisReceiptCount() async throws -> Int {
        guard let w = writer else { return 0 }
        let repo = FranklinDocumentRepository(db: w)
        return try repo.genesisLearningReceiptCount()
    }

    public func healingEventsCount() async throws -> Int {
        guard let w = writer else { return 0 }
        let repo = FranklinDocumentRepository(db: w)
        return try repo.healingEventsCount()
    }

    public func healingEventsSince(iso: String) async throws -> Int {
        guard let w = writer else { return 0 }
        let repo = FranklinDocumentRepository(db: w)
        return try repo.healingEventsSince(healedAtISO8601GreaterOrEqual: iso)
    }
}
