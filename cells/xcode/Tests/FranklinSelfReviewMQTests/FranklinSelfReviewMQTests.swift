import Darwin
import Foundation
import GRDB
import Testing
import GaiaFTCLCore
import GaiaGateKit
import VQbitSubstrate
@testable import FranklinConsciousness

private struct StubSovereigntyPass: SovereigntyProvider {
    func validate() async -> FranklinConsciousnessActor.PostWakeValidation {
        FranklinConsciousnessActor.PostWakeValidation(
            allPrimssovereign: true,
            unmoored: [],
            genesisReceiptPresent: true,
            healingEventsThisWake: 0
        )
    }
}

private struct StubSovereigntyFail: SovereigntyProvider {
    func validate() async -> FranklinConsciousnessActor.PostWakeValidation {
        FranklinConsciousnessActor.PostWakeValidation(
            allPrimssovereign: false,
            unmoored: [UUID()],
            genesisReceiptPresent: false,
            healingEventsThisWake: 0
        )
    }
}

private final class PhaseCounter: @unchecked Sendable {
    var value = 0
}

private func withMQSelfReviewSkipWire<T>(_ run: () async throws -> T) async rethrows -> T {
    setenv("GAIAFTCL_MQ_SELF_REVIEW_SKIP_WIRE", "1", 1)
    setenv("GAIAFTCL_MQ_SELF_REVIEW_SKIP_TENSOR", "1", 1)
    defer {
        unsetenv("GAIAFTCL_MQ_SELF_REVIEW_SKIP_WIRE")
        unsetenv("GAIAFTCL_MQ_SELF_REVIEW_SKIP_TENSOR")
    }
    return try await run()
}

@Suite("MQ-SR — Franklin self-review (GAMP5-OQ-PROTOCOL-002)", .serialized)
struct FranklinSelfReviewMQTests {
    @Test("MQ-SR-001: franklin_review_cycles receives at least one row per exercised domain cycle")
    func testReviewCycleInsertsRow() async throws {
        try await withMQSelfReviewSkipWire {
            await ManifoldProjectionStore.shared.resetForTests()
            let queue = try SubstrateDatabase.testQueue()
            await FranklinSubstrate.shared.bootstrapForTests(queue)
            let iso = ISO8601DateFormatter().string(from: Date())
            try LanguageGameContractSeeder.seedCanonicalContracts(writer: queue, timestampISO: iso)
            try await queue.write { db in
                try db.execute(sql: "UPDATE language_game_contracts SET review_interval_seconds = 0")
            }

            let counter = PhaseCounter()
            let harness = FranklinSelfReviewCycle(
                sovereigntyProvider: StubSovereigntyPass(),
                healthSampler: { _, _ in
                    counter.value += 1
                    return counter.value % 2 == 1 ? 0.2 : 0.95
                }
            )
            let repo = FranklinDocumentRepository(db: queue)
            let surfaces = try repo.fetchLanguageGameContractSurfaces()
            await harness.runSingleDomainCycle(domain: "fusion", sessionID: "mq-sr-001", surfaces: surfaces)

            let n = try await queue.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM franklin_review_cycles") ?? 0
            }
            #expect(n >= 1)
        }
    }

    @Test("MQ-SR-002: domain_improvement receipt on improvement path")
    func testImprovementReceiptWritten() async throws {
        try await withMQSelfReviewSkipWire {
            await ManifoldProjectionStore.shared.resetForTests()
            let queue = try SubstrateDatabase.testQueue()
            await FranklinSubstrate.shared.bootstrapForTests(queue)
            let iso = ISO8601DateFormatter().string(from: Date())
            try LanguageGameContractSeeder.seedCanonicalContracts(writer: queue, timestampISO: iso)
            try await queue.write { db in
                try db.execute(sql: "UPDATE language_game_contracts SET review_interval_seconds = 0")
            }

            let counter = PhaseCounter()
            let harness = FranklinSelfReviewCycle(
                sovereigntyProvider: StubSovereigntyPass(),
                healthSampler: { _, _ in
                    counter.value += 1
                    return counter.value % 2 == 1 ? 0.15 : 0.93
                }
            )
            let surfaces = try FranklinDocumentRepository(db: queue).fetchLanguageGameContractSurfaces()
            await harness.runSingleDomainCycle(domain: "fusion", sessionID: "mq-sr-002", surfaces: surfaces)

            let n = try await queue.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM franklin_learning_receipts WHERE kind = 'domain_improvement'"
                ) ?? 0
            }
            #expect(n >= 1)
        }
    }

    @Test("MQ-SR-003: aesthetic weights never regress when already at ceiling")
    func testNeverRegressWeight() async throws {
        try await withMQSelfReviewSkipWire {
            await ManifoldProjectionStore.shared.resetForTests()
            let queue = try SubstrateDatabase.testQueue()
            await FranklinSubstrate.shared.bootstrapForTests(queue)
            let iso = ISO8601DateFormatter().string(from: Date())
            try LanguageGameContractSeeder.seedCanonicalContracts(writer: queue, timestampISO: iso)
            try await queue.write { db in
                try db.execute(sql: "UPDATE language_game_contracts SET review_interval_seconds = 0")
            }

            let ceiling = AestheticRulesEnvelope(
                schema_version: 1,
                weights: .init(s1_weight: 1.0, s2_weight: 1.0, s3_weight: 1.0, s4_weight: 1.0)
            )
            let ceilingJSON = try AestheticRulesCodec.canonicalJSONString(ceiling)
            try await queue.write { db in
                try db.execute(
                    sql: "UPDATE language_game_contracts SET aesthetic_rules_json = ? WHERE lower(domain) = 'fusion'",
                    arguments: [ceilingJSON]
                )
            }

            let counter = PhaseCounter()
            let harness = FranklinSelfReviewCycle(
                sovereigntyProvider: StubSovereigntyPass(),
                healthSampler: { _, _ in
                    counter.value += 1
                    return counter.value % 2 == 1 ? 0.1 : 0.99
                }
            )
            let surfaces = try FranklinDocumentRepository(db: queue).fetchLanguageGameContractSurfaces()
            await harness.runSingleDomainCycle(domain: "fusion", sessionID: "mq-sr-003", surfaces: surfaces)

            let row = try await queue.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT aesthetic_rules_json FROM language_game_contracts WHERE lower(domain)='fusion'"
                )
            }
            #expect(row == ceilingJSON)
            let receipts = try await queue.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM franklin_learning_receipts WHERE kind='domain_improvement' AND session_id='mq-sr-003'"
                ) ?? 0
            }
            #expect(receipts == 0)
        }
    }

    @Test("MQ-SR-004: calorie threshold must exceed cure threshold before cycling")
    func testCalorieThresholdGTCureThreshold() async throws {
        try await withMQSelfReviewSkipWire {
            await ManifoldProjectionStore.shared.resetForTests()
            let queue = try SubstrateDatabase.testQueue()
            await FranklinSubstrate.shared.bootstrapForTests(queue)
            let iso = ISO8601DateFormatter().string(from: Date())
            try LanguageGameContractSeeder.seedCanonicalContracts(writer: queue, timestampISO: iso)
            try await queue.write { db in
                try db.execute(
                    sql: """
                    UPDATE language_game_contracts
                    SET constitutional_threshold_calorie = 0.4,
                        constitutional_threshold_cure = 0.7,
                        review_interval_seconds = 0
                    WHERE lower(domain) = 'fusion'
                    """
                )
            }

            let harness = FranklinSelfReviewCycle(
                sovereigntyProvider: StubSovereigntyPass(),
                healthSampler: { _, _ in 0.3 }
            )
            let surfaces = try FranklinDocumentRepository(db: queue).fetchLanguageGameContractSurfaces()
            await harness.runSingleDomainCycle(domain: "fusion", sessionID: "mq-sr-004", surfaces: surfaces)

            let n = try await queue.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM franklin_review_cycles WHERE domain='fusion'"
                ) ?? 0
            }
            #expect(n == 0)
        }
    }

    @Test("MQ-SR-005: review blocked when sovereignty reports unmoored prims")
    func testReviewBlocksOnUnmooredPrim() async throws {
        try await withMQSelfReviewSkipWire {
            await ManifoldProjectionStore.shared.resetForTests()
            let queue = try SubstrateDatabase.testQueue()
            await FranklinSubstrate.shared.bootstrapForTests(queue)
            let iso = ISO8601DateFormatter().string(from: Date())
            try LanguageGameContractSeeder.seedCanonicalContracts(writer: queue, timestampISO: iso)
            try await queue.write { db in
                try db.execute(sql: "UPDATE language_game_contracts SET review_interval_seconds = 0")
            }

            let harness = FranklinSelfReviewCycle(
                sovereigntyProvider: StubSovereigntyFail(),
                healthSampler: { _, _ in 0.99 }
            )
            await harness.runOncePass(sessionID: "mq-sr-005")

            let n = try await queue.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM franklin_review_cycles") ?? 0
            }
            #expect(n == 0)
        }
    }
}
