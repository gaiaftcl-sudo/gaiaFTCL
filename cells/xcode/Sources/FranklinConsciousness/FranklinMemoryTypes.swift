import CryptoKit
import Foundation
import GRDB
import GaiaFTCLCore

// MARK: — C4Snapshot

public struct C4Snapshot: Codable, Sendable, Equatable {
    public var c1_trust: Double
    public var c2_identity: Double
    public var c3_closure: Double
    public var c4_consequence: Double

    public init(
        c1_trust: Double = 0,
        c2_identity: Double = 0,
        c3_closure: Double = 0,
        c4_consequence: Double = 0
    ) {
        self.c1_trust = c1_trust
        self.c2_identity = c2_identity
        self.c3_closure = c3_closure
        self.c4_consequence = c4_consequence
    }

    public static let zero = C4Snapshot()
}

// MARK: — C4MemoryEvent

public struct C4MemoryEvent: Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case fusionCatalog     = "fusion_catalog"
        case healthProtocol    = "health_protocol"
        case selfReflection    = "self_reflection"
        case silenceTransition = "silence_transition"
        case innerMonologue    = "inner_monologue"
        case reflection
        case consciousness
        case conversation
        case learning
    }

    public let id: String
    public let sessionID: String
    public let kind: Kind
    public let text: String
    public let c4Snapshot: C4Snapshot
    public let terminalState: TerminalState
    public let timestampISO: String

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        kind: Kind,
        text: String,
        c4Snapshot: C4Snapshot,
        terminalState: TerminalState,
        timestampISO: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.text = text
        self.c4Snapshot = c4Snapshot
        self.terminalState = terminalState
        self.timestampISO = timestampISO ?? ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: — RestoredMemory

public struct RestoredMemory: Sendable {
    public let events: [C4MemoryEvent]
    public let derivedC4: C4Snapshot

    public init(events: [C4MemoryEvent], derivedC4: C4Snapshot) {
        self.events = events
        self.derivedC4 = derivedC4
    }

    public static let empty = RestoredMemory(events: [], derivedC4: .zero)
}

// MARK: — FranklinMemoryRepository

public final class FranklinMemoryRepository: Sendable {
    private let db: any DatabaseWriter

    public init(db: any DatabaseWriter) {
        self.db = db
    }

    /// Insert if not already present; returns true if newly inserted.
    public func insertIfAbsent(_ event: C4MemoryEvent) throws -> Bool {
        let snapshotJSON = snapshotJSON(event.c4Snapshot)
        let sha = computeSha(id: event.id, text: event.text, snapshotJSON: snapshotJSON)
        return try db.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO franklin_memories
                  (id, session_id, kind, text, c4_snapshot, terminal_state, sha256, timestamp_iso)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id, event.sessionID, event.kind.rawValue, event.text,
                    snapshotJSON, event.terminalState.rawValue, sha, event.timestampISO,
                ]
            )
            return db.changesCount > 0
        }
    }

    public func insert(_ event: C4MemoryEvent) throws {
        _ = try insertIfAbsent(event)
    }

    public func fetchAll() throws -> [C4MemoryEvent] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, session_id, kind, text, c4_snapshot, terminal_state, timestamp_iso FROM franklin_memories ORDER BY timestamp_iso ASC"
            )
            return rows.compactMap { decodeRow($0) }
        }
    }

    public func integrityViolations() -> Int { 0 }

    public func causalMagnitude(fromEventID eventID: String, inMemoryFallback fallback: Double) throws -> Double {
        do {
            return try db.read { db in
                let count = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM causal_edges WHERE source_id = ?",
                    arguments: [eventID]
                ) ?? 0
                if count == 0 { return fallback }
                let weight = try Double.fetchOne(
                    db,
                    sql: "SELECT AVG(edge_weight) FROM causal_edges WHERE source_id = ?",
                    arguments: [eventID]
                ) ?? fallback
                return weight
            }
        } catch {
            // causal_edges removed in v2 migration — return in-memory value
            return fallback
        }
    }

    private func snapshotJSON(_ snapshot: C4Snapshot) -> String {
        let d = (try? JSONEncoder().encode(snapshot)) ?? Data()
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    private func computeSha(id: String, text: String, snapshotJSON: String) -> String {
        let input = "\(id)\(text)\(snapshotJSON)".data(using: .utf8) ?? Data()
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private func decodeRow(_ row: Row) -> C4MemoryEvent? {
        guard let id: String = row["id"],
              let sessionID: String = row["session_id"],
              let kindStr: String = row["kind"],
              let kind = C4MemoryEvent.Kind(rawValue: kindStr),
              let text: String = row["text"],
              let snapshotStr: String = row["c4_snapshot"],
              let snapshotData = snapshotStr.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(C4Snapshot.self, from: snapshotData),
              let terminalStr: String = row["terminal_state"],
              let terminal = TerminalState(rawValue: terminalStr)
        else { return nil }
        let ts: String? = row["timestamp_iso"]
        return C4MemoryEvent(
            id: id, sessionID: sessionID, kind: kind, text: text,
            c4Snapshot: snapshot, terminalState: terminal, timestampISO: ts
        )
    }
}

// MARK: — C4MemoryStore

public actor C4MemoryStore {
    public static let shared = C4MemoryStore()

    private var repository: FranklinMemoryRepository?
    private var _sessionID: String = ""
    private var cachedEvents: [C4MemoryEvent] = []
    private var _state: C4Snapshot = .zero
    private var _violations: Int = 0
    private let localFallbackPath: URL?

    public init() {
        self.localFallbackPath = nil
    }

    public init(nats: NATSBridge, localFallbackPath: URL) {
        self.localFallbackPath = localFallbackPath
    }

    public func setup(memoryRepository: FranklinMemoryRepository) {
        repository = memoryRepository
        cachedEvents = []
        _state = .zero
        _violations = 0
    }

    public func setSessionID(_ id: String) {
        _sessionID = id
    }

    public func restore() -> RestoredMemory {
        var events: [C4MemoryEvent] = []
        var violations = 0

        if let fallbackURL = localFallbackPath {
            let (loaded, viols) = loadJSONL(from: fallbackURL)
            violations += viols
            for event in loaded {
                if let repo = repository {
                    let inserted = (try? repo.insertIfAbsent(event)) ?? false
                    if inserted {
                        events.append(event)
                    } else {
                        violations += 1
                    }
                } else {
                    events.append(event)
                }
            }
        } else {
            events = (try? repository?.fetchAll()) ?? []
        }

        cachedEvents = events
        _state = meanSnapshot(of: events)
        _violations = violations
        return RestoredMemory(events: events, derivedC4: _state)
    }

    public func record(_ event: C4MemoryEvent) {
        cachedEvents.append(event)
        _state = meanSnapshot(of: cachedEvents)
        try? repository?.insert(event)
    }

    public func currentState() -> C4Snapshot { _state }

    public func integrityViolations() -> Int { _violations }

    public func recall(query: String, limit: Int) -> [C4MemoryEvent] {
        let q = query.lowercased()
        return Array(cachedEvents.filter { $0.text.lowercased().contains(q) }.suffix(limit))
    }

    private func loadJSONL(from url: URL) -> ([C4MemoryEvent], violations: Int) {
        guard let data = try? Data(contentsOf: url) else { return ([], 0) }
        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
        var events: [C4MemoryEvent] = []
        var violations = 0
        let dec = JSONDecoder()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            guard let event = try? dec.decode(C4MemoryEvent.self, from: lineData) else {
                violations += 1
                continue
            }
            // Check sha256 if present in raw JSON
            if let rawDict = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
               let storedSha = rawDict["sha256"] as? String
            {
                let snapshotJSON = (rawDict["c4Snapshot"].flatMap { v -> String? in
                    let d = (try? JSONSerialization.data(withJSONObject: v)) ?? Data()
                    return String(data: d, encoding: .utf8)
                }) ?? "{}"
                let id = (rawDict["id"] as? String) ?? ""
                let text = (rawDict["text"] as? String) ?? ""
                let computed = sha256Hex(id: id, text: text, snapshotJSON: snapshotJSON)
                if storedSha != computed {
                    violations += 1
                    continue
                }
            }
            events.append(event)
        }
        return (events, violations)
    }

    private func sha256Hex(id: String, text: String, snapshotJSON: String) -> String {
        let input = "\(id)\(text)\(snapshotJSON)".data(using: .utf8) ?? Data()
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private func meanSnapshot(of events: [C4MemoryEvent]) -> C4Snapshot {
        guard !events.isEmpty else { return .zero }
        let n = Double(events.count)
        return C4Snapshot(
            c1_trust: events.map(\.c4Snapshot.c1_trust).reduce(0, +) / n,
            c2_identity: events.map(\.c4Snapshot.c2_identity).reduce(0, +) / n,
            c3_closure: events.map(\.c4Snapshot.c3_closure).reduce(0, +) / n,
            c4_consequence: events.map(\.c4Snapshot.c4_consequence).reduce(0, +) / n
        )
    }
}

// MARK: — FranklinProfile

public struct FranklinProfile: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var created: String

    public init() {
        self.created = ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: — FranklinSelfModel

public actor FranklinSelfModel {
    public static let shared = FranklinSelfModel()

    public struct PriorityWeights: Sendable {
        public var closureWeight: Double = 0.35
        public var trustWeight: Double = 0.25
        public var identityWeight: Double = 0.20
        public var consequenceWeight: Double = 0.20
    }

    public struct ProfileSnapshot: Sendable {
        public var explorationRate: Double = 0.20
        public var priorityWeights: PriorityWeights = PriorityWeights()
        public var characterNarrative: String = ""
    }

    public private(set) var version: Int = 1
    private var _snapshot: ProfileSnapshot = ProfileSnapshot()

    public func snapshot() -> ProfileSnapshot { _snapshot }

    @discardableResult
    public func mutate(reason: String, _ transform: (inout ProfileSnapshot) -> Void) -> ProfileSnapshot {
        transform(&_snapshot)
        return _snapshot
    }

    public func applyOutcome(_ outcome: TerminalOutcome) {
        version += 1
        switch outcome.terminal {
        case .blocked:
            _snapshot.explorationRate = min(_snapshot.explorationRate + 0.01, 0.50)
        case .calorie:
            _snapshot.explorationRate = max(_snapshot.explorationRate - 0.01, 0.10)
        default:
            break
        }
        _snapshot.priorityWeights.closureWeight += 0.001
    }

    public func appendNarrative(_ text: String) {
        if _snapshot.characterNarrative.isEmpty {
            _snapshot.characterNarrative = text
        } else {
            _snapshot.characterNarrative += " " + text
        }
    }

    public func resetForTests() {
        version = 1
        _snapshot = ProfileSnapshot()
    }
}

// MARK: — AutonomyEnvelope

public actor AutonomyEnvelope {
    public static let shared = AutonomyEnvelope()

    public struct Band: Sendable {
        public var center: Double = 0.5
        public var width: Double = 0.3
    }

    private var _band: Band = Band()

    public func currentBand() -> Band { _band }

    public func update(from outcome: TerminalOutcome) {
        switch outcome.terminal {
        case .calorie:
            _band.center = min(_band.center + 0.02, 0.95)
        case .blocked:
            _band.center = max(_band.center - 0.01, 0.05)
        default:
            break
        }
    }

    public func summaryLine() -> String {
        "autonomy_envelope v1: center=\(String(format: "%.3f", _band.center)) width=\(String(format: "%.3f", _band.width))"
    }

    public func resetForTests() {
        _band = Band()
    }
}

// MARK: — FranklinSelfModel

public actor FranklinDecisionSampler {
    public static let shared = FranklinDecisionSampler()
    private var seed: Int = 42

    public func resetSeedForTests(_ seed: Int) {
        self.seed = seed
    }

    public func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed & 0x7FFFFFFF) / Double(0x7FFFFFFF)
    }
}

// MARK: — AutonomyPaths

public enum AutonomyPaths {
    public static func learningReceiptsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL/learning_receipts", isDirectory: true)
    }
}

// MARK: — ConsciousnessReceipt

public struct ConsciousnessReceipt: Codable, Sendable {
    public let state: TerminalState
    public let sessionID: String
    public let memoryCount: Int
    public let reason: String

    public init(state: TerminalState, sessionID: String, memoryCount: Int, reason: String) {
        self.state = state
        self.sessionID = sessionID
        self.memoryCount = memoryCount
        self.reason = reason
    }
}

// MARK: — SilenceCommand

public struct SilenceCommand: Decodable, Sendable {
    public let operatorSignature: String
    public let silenced: Bool

    enum CodingKeys: String, CodingKey {
        case operatorSignature = "operator_signature"
        case silenced
    }
}

// MARK: — FranklinUtterance

public struct FranklinUtterance: Sendable {
    public enum Priority: Sendable { case consciousness, high, reflection }
    public enum Source: Sendable { case selfAwareness, innerMonologue }

    public let text: String
    public let priority: Priority
    public let source: Source

    public init(text: String, priority: Priority, source: Source) {
        self.text = text
        self.priority = priority
        self.source = source
    }
}

// MARK: — TerminalOutcome

public struct TerminalOutcome: Sendable {
    public let terminal: TerminalState
    public let c4: C4Snapshot
    public let source: String

    public static func make(terminal: TerminalState, c4: C4Snapshot, source: String) -> TerminalOutcome {
        TerminalOutcome(terminal: terminal, c4: c4, source: source)
    }

    private init(terminal: TerminalState, c4: C4Snapshot, source: String) {
        self.terminal = terminal
        self.c4 = c4
        self.source = source
    }
}

// MARK: — LanguageGameCatalog

public enum LanguageGameCatalog {
    public enum Domain: Sendable { case fusion, health }

    public struct LanguageGame: Sendable {
        public let id: String
        public let title: String
    }

    public static func games(for domain: Domain) -> [LanguageGame] {
        switch domain {
        case .fusion:
            return [LanguageGame(id: "FUSION-001", title: "Fusion Language Game")]
        case .health:
            return [LanguageGame(id: "HEALTH-001", title: "Health Protocol Language Game")]
        }
    }
}
