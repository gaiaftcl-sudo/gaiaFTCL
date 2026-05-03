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

    migrator.registerMigration("v7_domain_standards") { db in
        try db.alter(table: "language_game_contracts") { t in
            t.add(column: "constitutional_threshold_calorie", .double).defaults(to: 0.8)
            t.add(column: "constitutional_threshold_cure", .double).defaults(to: 0.6)
            t.add(column: "improvement_target", .double).defaults(to: 0.05)
            t.add(column: "review_interval_seconds", .integer).defaults(to: 300)
            t.add(column: "aesthetic_rules_json", .text)
        }
        let baseline = try AestheticRulesCodec.canonicalJSONString(.bootstrapDefaults())
        try db.execute(
            sql: """
            UPDATE language_game_contracts SET
              constitutional_threshold_calorie = 0.8,
              constitutional_threshold_cure = 0.6,
              improvement_target = 0.05,
              review_interval_seconds = 300,
              aesthetic_rules_json = ?
            WHERE aesthetic_rules_json IS NULL
            """,
            arguments: [baseline]
        )
    }

    migrator.registerMigration("v8_review_cycles") { db in
        try db.create(table: "franklin_review_cycles", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("domain", .text).notNull()
            t.column("cycle_started_at", .text).notNull()
            t.column("cycle_ended_at", .text)
            t.column("prior_health_score", .double)
            t.column("post_health_score", .double)
            t.column("health_score", .double)
            t.column("threshold", .double)
            t.column("action_taken", .text)
            t.column("outcome", .text)
            t.column("receipt_id", .text)
        }
        try db.create(
            index: "idx_review_cycles_domain",
            on: "franklin_review_cycles",
            columns: ["domain"]
        )
        try db.create(
            index: "idx_review_cycles_started",
            on: "franklin_review_cycles",
            columns: ["cycle_started_at"]
        )
    }

    /// Rows inserted after **`v7`** via **`INSERT OR IGNORE`** may omit **`aesthetic_rules_json`** — backfill for **`improveDomainStandard`** decoding.
    migrator.registerMigration("v9_contract_aesthetic_backfill") { db in
        let baseline = try AestheticRulesCodec.canonicalJSONString(.bootstrapDefaults())
        try db.execute(
            sql: """
            UPDATE language_game_contracts
            SET aesthetic_rules_json = ?
            WHERE aesthetic_rules_json IS NULL OR trim(aesthetic_rules_json) = ''
            """,
            arguments: [baseline]
        )
    }

    /// Six quantum family **`language_game_contracts`** rows (**IQ‑QM‑005**) — thresholds / **`aesthetic_rules_json`** match **[`docs/reports/GAMP5-VQBIT-QUANTUM-IQ-OQ-PQ-001.md`]**.
    migrator.registerMigration("v10_quantum_domains") { db in
        try db.execute(sql: """
            INSERT OR IGNORE INTO language_game_contracts
              (id, game_id, cell_id, contract_doc, status, timestamp_iso, domain, contract_sha256,
               constitutional_threshold_calorie, constitutional_threshold_cure, improvement_target, review_interval_seconds, aesthetic_rules_json)
            VALUES (
              'lgc-QC-CIRCUIT-001', 'QC-CIRCUIT-001', 'gaiaftcl-mac-cell', '{"created_at":"2026-05-03T00:00:00Z","domain":"quantum_circuit","game_id":"QC-CIRCUIT-001","invariant_refs":["INV-QC-CIRCUIT-001"],"prim_paths":["/World/Quantum/CircuitFamily"],"s1_semantic":"bond_dimension_coherence","s2_semantic":"entanglement_entropy_stability","s3_semantic":"interaction_field_connectivity","s4_semantic":"bell_chsh_enforcement","sha256":"ec6dcdb0a333e51b5282f406b3e0940ba27a144b33ac4ea3200e4361bea04002"}', 'active', '2026-05-03T00:00:00Z', 'quantum_circuit', 'f89dfeb52ecb0be85a2594175b23184f2319706ff6508a71c1285fdc3cee3901',
              0.85, 0.6, 0.05, 300, '{"chsh_bound":2.01,"frontiers":{"AmpAmp_n_max":10,"Grover_n_max":12,"QFT_n_max":16,"QPE_n_max":10,"Shor_N_max":15},"max_bond_dim":1024,"schema_version":1,"weights":{"s1_weight":0.3,"s2_weight":0.25,"s3_weight":0.25,"s4_weight":0.2}}'
            )
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO language_game_contracts
              (id, game_id, cell_id, contract_doc, status, timestamp_iso, domain, contract_sha256,
               constitutional_threshold_calorie, constitutional_threshold_cure, improvement_target, review_interval_seconds, aesthetic_rules_json)
            VALUES (
              'lgc-QC-VARIATIONAL-001', 'QC-VARIATIONAL-001', 'gaiaftcl-mac-cell', '{"created_at":"2026-05-03T00:00:00Z","domain":"quantum_variational","game_id":"QC-VARIATIONAL-001","invariant_refs":["INV-QC-VAR-001"],"prim_paths":["/World/Quantum/VariationalFamily"],"s1_semantic":"ansatz_coherence","s2_semantic":"parameter_convergence","s3_semantic":"coupling_field_connectivity","s4_semantic":"cost_landscape_visibility","sha256":"e8ad2790d952b4d75e15725a3b4127b2cf2473203e36e1e8c4e0c699d171e798"}', 'active', '2026-05-03T00:00:00Z', 'quantum_variational', 'f85852e298fcb282d52b2a51f6497937adada51f1becc99a27ecc9fc46e00078',
              0.8, 0.55, 0.05, 300, '{"frontiers":{"Classifier_qubits":4,"QAOA_qubits":8,"QUBO_vars":8,"VQE_qubits":6},"schema_version":1,"weights":{"s1_weight":0.25,"s2_weight":0.3,"s3_weight":0.25,"s4_weight":0.2}}'
            )
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO language_game_contracts
              (id, game_id, cell_id, contract_doc, status, timestamp_iso, domain, contract_sha256,
               constitutional_threshold_calorie, constitutional_threshold_cure, improvement_target, review_interval_seconds, aesthetic_rules_json)
            VALUES (
              'lgc-QC-LINALG-001', 'QC-LINALG-001', 'gaiaftcl-mac-cell', '{"created_at":"2026-05-03T00:00:00Z","domain":"quantum_linear_algebra","game_id":"QC-LINALG-001","invariant_refs":["INV-QC-LA-001"],"prim_paths":["/World/Quantum/LinearAlgebraFamily"],"s1_semantic":"matrix_rank_coherence","s2_semantic":"singular_value_stability","s3_semantic":"block_encoding_connectivity","s4_semantic":"eigenvalue_visibility","sha256":"378f6067c3ab44258fa2afe10ef2f8ab5b4bc69ddd704423fdc176b8f4b3394a"}', 'active', '2026-05-03T00:00:00Z', 'quantum_linear_algebra', 'a8f8084866f4bdd15321aa7d7fef34181077d9121b84f896685761fd0afd3cb6',
              0.7, 0.4, 0.05, 300, '{"frontiers":{"HHL_dim":16,"QSVT_rank":8,"qPCA_rank":4},"note":"All 3 BOUNDED - threshold reflects frontier proximity","schema_version":1,"weights":{"s1_weight":0.35,"s2_weight":0.25,"s3_weight":0.2,"s4_weight":0.2}}'
            )
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO language_game_contracts
              (id, game_id, cell_id, contract_doc, status, timestamp_iso, domain, contract_sha256,
               constitutional_threshold_calorie, constitutional_threshold_cure, improvement_target, review_interval_seconds, aesthetic_rules_json)
            VALUES (
              'lgc-QC-SIMULATION-001', 'QC-SIMULATION-001', 'gaiaftcl-mac-cell', '{"created_at":"2026-05-03T00:00:00Z","domain":"quantum_simulation","game_id":"QC-SIMULATION-001","invariant_refs":["INV-QC-SIM-001"],"prim_paths":["/World/Quantum/SimulationFamily"],"s1_semantic":"adjacency_field_integrity","s2_semantic":"trotter_entropy_stability","s3_semantic":"hamiltonian_term_connectivity","s4_semantic":"evolution_observable_visibility","sha256":"102019b72256036d3a56b4b0b0665c0abd1ba1774901de9766f06c6d4b26df5d"}', 'active', '2026-05-03T00:00:00Z', 'quantum_simulation', 'd434f1b20b2ec1cf231b8791211803372e7c5ad8f0de99f8d802566acd7d54f3',
              0.82, 0.58, 0.05, 300, '{"frontiers":{"CTQW_nodes":16,"HamSim_qubits":4,"HamSim_trotter_steps":10},"schema_version":1,"weights":{"s1_weight":0.25,"s2_weight":0.3,"s3_weight":0.3,"s4_weight":0.15}}'
            )
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO language_game_contracts
              (id, game_id, cell_id, contract_doc, status, timestamp_iso, domain, contract_sha256,
               constitutional_threshold_calorie, constitutional_threshold_cure, improvement_target, review_interval_seconds, aesthetic_rules_json)
            VALUES (
              'lgc-QC-BOSONIC-001', 'QC-BOSONIC-001', 'gaiaftcl-mac-cell', '{"created_at":"2026-05-03T00:00:00Z","domain":"quantum_bosonic","game_id":"QC-BOSONIC-001","invariant_refs":["INV-QC-BOS-001"],"prim_paths":["/World/Quantum/BosonicFamily"],"s1_semantic":"fock_space_decomposition","s2_semantic":"photon_mode_entropy_stability","s3_semantic":"interferometer_connectivity","s4_semantic":"permanent_hafnian_visibility","sha256":"dc71b078c546d8193d490f70cc864aa24396c39fdc9c5c92688c1160a548585c"}', 'active', '2026-05-03T00:00:00Z', 'quantum_bosonic', 'aefd45edc89eb87d9ceb27f31d038e755273d2d5942e878168398b9aace35471',
              0.88, 0.65, 0.05, 300, '{"complexity":"#P-hard beyond frontier - additive BPP within","frontiers":{"BosonSampling_photons":3,"GBS_modes":4},"schema_version":1,"weights":{"s1_weight":0.3,"s2_weight":0.2,"s3_weight":0.25,"s4_weight":0.25}}'
            )
            """)
        try db.execute(sql: """
            INSERT OR IGNORE INTO language_game_contracts
              (id, game_id, cell_id, contract_doc, status, timestamp_iso, domain, contract_sha256,
               constitutional_threshold_calorie, constitutional_threshold_cure, improvement_target, review_interval_seconds, aesthetic_rules_json)
            VALUES (
              'lgc-QC-ERRORCORR-001', 'QC-ERRORCORR-001', 'gaiaftcl-mac-cell', '{"created_at":"2026-05-03T00:00:00Z","domain":"quantum_error_correction","game_id":"QC-ERRORCORR-001","invariant_refs":["INV-QC-QEC-001"],"prim_paths":["/World/Quantum/ErrorCorrectionFamily"],"s1_semantic":"stabilizer_field_integrity","s2_semantic":"syndrome_entropy_stability","s3_semantic":"pauli_group_connectivity","s4_semantic":"correction_observable_visibility","sha256":"8ede442c4db218f3ce2b9df127bffc6d3baaa86f06d00cfb95bb650869a16c9e"}', 'active', '2026-05-03T00:00:00Z', 'quantum_error_correction', '775e3cb8479f5c9cce6b3a05877a0fa6a911db92c014ecc43191b4da1a2f2a84',
              0.75, 0.45, 0.05, 300, '{"frontiers":{"Steane_qubits":7,"Surface_lattice":"3x3","Topological_anyons":3,"braid_depth":8},"note":"Steane EXECUTED via Gottesman-Knill. Surface+Topological BOUNDED.","schema_version":1,"weights":{"s1_weight":0.3,"s2_weight":0.25,"s3_weight":0.25,"s4_weight":0.2}}'
            )
            """)
    }
}
