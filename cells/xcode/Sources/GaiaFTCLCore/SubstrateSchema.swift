// NAMING CONTRACT — DO NOT VIOLATE
// VQbit8D    = Metal ABI struct in VQbit.swift — feeds shader argument buffers
//              field names are physics semantics (entropy, truth, etc.)
//              NEVER use for database row types
//
// VQbitRecord = GRDB row type for SQLite persistence
//               field names are substrate column names (s1_structural, etc.)
//               NEVER confuse with VQbit8D
//
// If you see VQbit8D used as a FetchableRecord or PersistableRecord,
// that is a bug. Fix it before proceeding.

import Foundation
import GRDB

/// SQLite row for persisted vQbit measurements (M⁸ substrate columns). Not Metal `VQbit8D`.
public struct VQbitRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "vqbits"

    public var id: String
    public var s1Structural: Double
    public var s2Temporal: Double
    public var s3Spatial: Double
    public var s4Observable: Double
    public var c1Trust: Double
    public var c2Identity: Double
    public var c3Closure: Double
    public var c4Consequence: Double
    public var terminalState: String
    public var envelopeID: String?
    public var cellID: String
    public var timestampISO: String

    enum CodingKeys: String, CodingKey {
        case id
        case s1Structural = "s1_structural"
        case s2Temporal = "s2_temporal"
        case s3Spatial = "s3_spatial"
        case s4Observable = "s4_observable"
        case c1Trust = "c1_trust"
        case c2Identity = "c2_identity"
        case c3Closure = "c3_closure"
        case c4Consequence = "c4_consequence"
        case terminalState = "terminal_state"
        case envelopeID = "envelope_id"
        case cellID = "cell_id"
        case timestampISO = "timestamp_iso"
    }
}

public func createSubstrateMigrations(_ migrator: inout DatabaseMigrator) {
    migrator.registerMigration("v1_core") { db in
        try db.create(table: "vqbits", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("s1_structural", .double).notNull()
            t.column("s2_temporal", .double).notNull()
            t.column("s3_spatial", .double).notNull()
            t.column("s4_observable", .double).notNull()
            t.column("c1_trust", .double).notNull()
            t.column("c2_identity", .double).notNull()
            t.column("c3_closure", .double).notNull()
            t.column("c4_consequence", .double).notNull()
            t.column("terminal_state", .text).notNull()
            t.column("envelope_id", .text)
            t.column("cell_id", .text).notNull()
            t.column("timestamp_iso", .text).notNull()
        }
        try db.create(index: "idx_vqbits_timestamp", on: "vqbits", columns: ["timestamp_iso"])
        try db.create(index: "idx_vqbits_terminal", on: "vqbits", columns: ["terminal_state"])

        try db.create(table: "envelopes", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("status", .text).notNull().defaults(to: "OPEN")
            t.column("ttl_seconds", .integer).notNull()
            t.column("opened_at", .text).notNull()
            t.column("closed_at", .text)
            t.column("terminal_state", .text)
            t.column("domain", .text).notNull()
            t.column("cell_id", .text).notNull()
        }
        try db.create(index: "idx_envelopes_status", on: "envelopes", columns: ["status", "opened_at"])

        try db.create(table: "causal_edges", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("source_id", .text).notNull()
            t.column("target_id", .text).notNull()
            t.column("edge_weight", .double).notNull().defaults(to: 1.0)
            t.column("edge_kind", .text).notNull()
            t.column("timestamp_iso", .text).notNull()
        }
        try db.create(index: "idx_causal_source", on: "causal_edges", columns: ["source_id"])

        try db.create(table: "franklin_memories", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("session_id", .text).notNull()
            t.column("kind", .text).notNull()
            t.column("text", .text).notNull()
            t.column("c4_snapshot", .text).notNull()
            t.column("terminal_state", .text).notNull()
            t.column("sha256", .text).notNull()
            t.column("timestamp_iso", .text).notNull()
        }
        try db.create(index: "idx_memories_timestamp", on: "franklin_memories", columns: ["timestamp_iso"])
        try db.create(index: "idx_memories_kind", on: "franklin_memories", columns: ["kind"])

        try db.create(virtualTable: "franklin_memories_fts", using: FTS5()) { t in
            t.synchronize(withTable: "franklin_memories")
            t.column("text")
            t.column("kind")
        }

        try db.create(table: "language_game_contracts", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("game_id", .text).notNull()
            t.column("cell_id", .text).notNull()
            t.column("contract_doc", .text).notNull()
            t.column("status", .text).notNull()
            t.column("timestamp_iso", .text).notNull()
        }

        try db.create(table: "cell_identity", ifNotExists: true) { t in
            t.primaryKey("cell_id", .text)
            t.column("s4c4_hash", .text).notNull()
            t.column("constitution", .text).notNull()
            t.column("last_verified", .text).notNull()
        }

        try db.create(table: "franklin_autonomy_envelope", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("snapshot", .text).notNull()
            t.column("version", .integer).notNull()
            t.column("timestamp_iso", .text).notNull()
        }

        try db.create(table: "franklin_self_model_history", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("version", .integer).notNull()
            t.column("reason", .text).notNull()
            t.column("profile", .text).notNull()
            t.column("drift", .double).notNull().defaults(to: 0)
            t.column("narrative", .text).notNull().defaults(to: "")
            t.column("sha256", .text).notNull()
            t.column("timestamp_iso", .text).notNull()
        }

        try db.create(table: "franklin_learning_receipts", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("session_id", .text).notNull()
            t.column("terminal", .text).notNull()
            t.column("receipt_path", .text).notNull()
            t.column("receipt_sha256", .text).notNull()
            t.column("timestamp_iso", .text).notNull()
        }

        try db.create(table: "franklin_metalearning_events", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("payload", .text).notNull()
            t.column("timestamp_iso", .text).notNull()
        }
    }

    migrator.registerMigration("v2_remove_graph_tables") { db in
        try db.execute(sql: "DROP TABLE IF EXISTS vqbits")
        try db.execute(sql: "DROP TABLE IF EXISTS envelopes")
        try db.execute(sql: "DROP TABLE IF EXISTS causal_edges")
    }

    migrator.registerMigration("v3_genesis_receipt") { db in
        try db.alter(table: "franklin_learning_receipts") { t in
            t.add(column: "kind", .text)
            t.add(column: "payload_json", .text)
            t.add(column: "canonical_sha256", .text)
        }
    }

    migrator.registerMigration("v4_language_game_contract_surface") { db in
        try db.alter(table: "language_game_contracts") { t in
            t.add(column: "domain", .text)
            t.add(column: "contract_sha256", .text)
        }
    }

    migrator.registerMigration("v5_franklin_healing_events") { db in
        try db.create(table: "franklin_healing_events", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("prim_id", .text).notNull()
            t.column("reason", .integer).notNull()
            t.column("violation_code", .integer).notNull()
            t.column("healed_at", .text).notNull()
            t.column("outcome", .text)
        }
    }

    /// Read-only surface for operators and tooling — **one row per USD prim path** from **`contract_doc`**. Franklin / GaiaFTCL keep using typed Swift + JSON; this does not duplicate writes or affect C⁴.
    migrator.registerMigration("v6_language_game_contract_prim_paths_view") { db in
        try db.execute(sql: "DROP VIEW IF EXISTS language_game_contract_prim_paths")
        try db.execute(sql: """
            CREATE VIEW language_game_contract_prim_paths AS
            SELECT
              c.id AS contract_row_id,
              c.game_id AS game_id,
              c.domain AS domain,
              c.status AS status,
              j.value AS prim_path,
              c.timestamp_iso AS timestamp_iso
            FROM language_game_contracts AS c,
            json_each(json_extract(c.contract_doc, '$.prim_paths')) AS j
            WHERE json_extract(c.contract_doc, '$.prim_paths') IS NOT NULL
            """)
    }
}
