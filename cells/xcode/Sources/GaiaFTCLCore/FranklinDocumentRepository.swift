import Foundation
import GRDB

/// Typed persistence for Franklin substrate tables (no dynamic SQL table names).
public final class FranklinDocumentRepository: Sendable {
    private let db: any DatabaseWriter

    public init(db: any DatabaseWriter) {
        self.db = db
    }

    public func upsertAutonomyEnvelope(snapshotJSON: String, version: Int, timestampISO: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO franklin_autonomy_envelope (id, snapshot, version, timestamp_iso)
                VALUES ('current', ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  snapshot = excluded.snapshot,
                  version = excluded.version,
                  timestamp_iso = excluded.timestamp_iso
                """,
                arguments: [snapshotJSON, version, timestampISO]
            )
        }
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
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO franklin_self_model_history
                  (id, version, reason, profile, drift, narrative, sha256, timestamp_iso)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [id, version, reason, profileJSON, drift, narrative, sha256, timestampISO]
            )
        }
    }

    public func insertLearningReceipt(
        id: String,
        sessionID: String,
        terminal: String,
        receiptPath: String,
        receiptSha256: String,
        timestampISO: String
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO franklin_learning_receipts
                  (id, session_id, terminal, receipt_path, receipt_sha256, timestamp_iso)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [id, sessionID, terminal, receiptPath, receiptSha256, timestampISO]
            )
        }
    }

    /// Insert-or-ignore genesis receipt row (**`kind`** = **`genesis`**).
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
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO franklin_learning_receipts
                  (id, session_id, terminal, receipt_path, receipt_sha256, timestamp_iso, kind, payload_json, canonical_sha256)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id, sessionID, terminal, receiptPath, receiptSha256, timestampISO,
                    kind, payloadJSON, canonicalSha256,
                ]
            )
        }
    }

    /// Baseline self-model row — **`reason`** **`genesis`** (insert-or-ignore).
    public func insertSelfModelGenesisIfAbsent(
        id: String,
        version: Int,
        reason: String,
        profileJSON: String,
        drift: Double,
        narrative: String,
        sha256: String,
        timestampISO: String
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO franklin_self_model_history
                  (id, version, reason, profile, drift, narrative, sha256, timestamp_iso)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [id, version, reason, profileJSON, drift, narrative, sha256, timestampISO]
            )
        }
    }

    public func insertMetalearningEvent(id: String, payloadJSON: String, timestampISO: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO franklin_metalearning_events (id, payload, timestamp_iso)
                VALUES (?, ?, ?)
                """,
                arguments: [id, payloadJSON, timestampISO]
            )
        }
    }

    /// Insert-or-ignore language-game contract (**domain** surface columns + JSON **`contract_doc`**).
    public func insertLanguageGameContractIfAbsent(
        id: String,
        gameID: String,
        cellID: String,
        domain: String,
        contractDocJSON: String,
        contractSha256: String,
        status: String,
        timestampISO: String
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO language_game_contracts
                  (id, game_id, cell_id, contract_doc, status, timestamp_iso, domain, contract_sha256)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id, gameID, cellID, contractDocJSON, status, timestampISO, domain, contractSha256,
                ]
            )
        }
    }

    public func insertHealingEvent(
        id: String,
        primID: UUID,
        reason: Int,
        violationCode: Int,
        healedAtISO: String,
        outcome: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO franklin_healing_events (id, prim_id, reason, violation_code, healed_at, outcome)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [id, primID.uuidString, reason, violationCode, healedAtISO, outcome]
            )
        }
    }

    /// Rows needed for S⁴ sovereignty audit (**game_id**, **domain**, **prim_paths** from **`contract_doc`** JSON).
    public func fetchLanguageGameContractSurfaces() throws -> [(gameID: String, domain: String?, primPaths: [String])] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT game_id, domain, contract_doc FROM language_game_contracts WHERE lower(status) = 'active'"
            )
            var seen = Set<String>()
            var out: [(String, String?, [String])] = []
            for row in rows {
                let gameID: String = row["game_id"]
                guard !seen.contains(gameID) else { continue }
                seen.insert(gameID)
                let domain: String? = row["domain"]
                let doc: String = row["contract_doc"]
                guard let data = doc.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(LanguageGameContractDocument.self, from: data)
                else { continue }
                out.append((decoded.game_id, domain ?? decoded.domain, decoded.prim_paths))
            }
            return out
        }
    }

    public func genesisLearningReceiptCount() throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM franklin_learning_receipts WHERE kind = 'genesis'") ?? 0
        }
    }

    public func healingEventsCount() throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM franklin_healing_events") ?? 0
        }
    }

    public func healingEventsSince(healedAtISO8601GreaterOrEqual lowerBound: String) throws -> Int {
        try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM franklin_healing_events WHERE healed_at >= ?",
                arguments: [lowerBound]
            ) ?? 0
        }
    }

    // MARK: — Self-review (GAMP5-OQ-PROTOCOL-002)

    public struct LanguageGameContractStandardsRow: Sendable {
        public let id: String
        public let gameID: String
        public let domain: String
        public let constitutionalThresholdCalorie: Double
        public let constitutionalThresholdCure: Double
        public let improvementTarget: Double
        public let reviewIntervalSeconds: Int
        public let aestheticRulesJSON: String
    }

    public func fetchActiveContractStandards(domain: String) throws -> LanguageGameContractStandardsRow? {
        let key = domain.lowercased()
        return try db.read { db -> LanguageGameContractStandardsRow? in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT id, game_id, domain, constitutional_threshold_calorie, constitutional_threshold_cure,
                       improvement_target, review_interval_seconds, aesthetic_rules_json
                FROM language_game_contracts
                WHERE lower(domain) = ? AND lower(status) = 'active'
                LIMIT 1
                """,
                arguments: [key]
            ) else { return nil }
            let json: String = row["aesthetic_rules_json"] ?? ""
            return LanguageGameContractStandardsRow(
                id: row["id"],
                gameID: row["game_id"],
                domain: row["domain"],
                constitutionalThresholdCalorie: row["constitutional_threshold_calorie"] ?? 0.8,
                constitutionalThresholdCure: row["constitutional_threshold_cure"] ?? 0.6,
                improvementTarget: row["improvement_target"] ?? 0.05,
                reviewIntervalSeconds: row["review_interval_seconds"] ?? 300,
                aestheticRulesJSON: json
            )
        }
    }

    public func updateContractAestheticRules(contractID: String, aestheticRulesJSON: String, contractSha256: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                UPDATE language_game_contracts
                SET aesthetic_rules_json = ?, contract_sha256 = ?
                WHERE id = ?
                """,
                arguments: [aestheticRulesJSON, contractSha256, contractID]
            )
        }
    }

    public func insertFranklinReviewCycle(
        id: String,
        domain: String,
        cycleStartedAtISO: String,
        cycleEndedAtISO: String?,
        priorHealthScore: Double?,
        postHealthScore: Double?,
        healthScore: Double?,
        threshold: Double?,
        actionTaken: String?,
        outcome: String?,
        receiptID: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO franklin_review_cycles
                  (id, domain, cycle_started_at, cycle_ended_at, prior_health_score, post_health_score,
                   health_score, threshold, action_taken, outcome, receipt_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id, domain, cycleStartedAtISO, cycleEndedAtISO,
                    priorHealthScore, postHealthScore, healthScore, threshold,
                    actionTaken, outcome, receiptID,
                ]
            )
        }
    }

    public func insertLearningReceiptWithPayload(
        id: String,
        sessionID: String,
        terminal: String,
        receiptPath: String,
        receiptSha256: String,
        timestampISO: String,
        kind: String,
        payloadJSON: String,
        canonicalSha256: String
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO franklin_learning_receipts
                  (id, session_id, terminal, receipt_path, receipt_sha256, timestamp_iso, kind, payload_json, canonical_sha256)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id, sessionID, terminal, receiptPath, receiptSha256, timestampISO,
                    kind, payloadJSON, canonicalSha256,
                ]
            )
        }
    }
}
