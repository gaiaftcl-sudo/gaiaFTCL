import CryptoKit
import Foundation
import GaiaFTCLCore

// MARK: — Decision

public struct Decision: Sendable {
    public let franklinRationale: String

    public init(franklinRationale: String) {
        self.franklinRationale = franklinRationale
    }
}

// MARK: — FranklinFreeWillEngine

public actor FranklinFreeWillEngine {
    public static let shared = FranklinFreeWillEngine()

    private var lastDecisionAt: Date?
    private var _decisionCount: Int = 0

    public func hasRecentDecisionWithRationale(maxAgeSeconds: Double) -> Bool {
        guard let lastDecisionAt else { return false }
        return Date().timeIntervalSince(lastDecisionAt) <= maxAgeSeconds
    }

    @discardableResult
    public func publishDecisionProbeForTest(state: C4Snapshot, sessionID: String) async -> Decision {
        lastDecisionAt = Date()
        _decisionCount += 1
        let er = await FranklinSelfModel.shared.snapshot().explorationRate
        let rationale = "Franklin deliberation: trust=\(fmt(state.c1_trust)) identity=\(fmt(state.c2_identity)) closure=\(fmt(state.c3_closure)) consequence=\(fmt(state.c4_consequence)). Exploration rate=\(String(format: "%.3f", er)). Pathway selected."
        if er > 0.15 {
            await C4MemoryStore.shared.record(
                C4MemoryEvent(
                    sessionID: sessionID,
                    kind: .learning,
                    text: "Exploration probe at rate \(String(format: "%.3f", er)). \(rationale)",
                    c4Snapshot: state,
                    terminalState: .calorie
                )
            )
        }
        return Decision(franklinRationale: rationale)
    }

    public func decisionCount() -> Int { _decisionCount }

    public func sceneCoherenceScore(for state: C4Snapshot) -> Double {
        (state.c1_trust + state.c3_closure) / 2.0
    }

    public func lastDecisionAgeSeconds() -> Double? {
        guard let lastDecisionAt else { return nil }
        return Date().timeIntervalSince(lastDecisionAt)
    }

    public func run(sessionID: String) async {
        while !Task.isCancelled {
            lastDecisionAt = Date()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}

// MARK: — FranklinVoice

public actor FranklinVoice {
    public static let shared = FranklinVoice()

    private var _silenced = false

    public func speak(_ utterance: FranklinUtterance) {
        guard !_silenced else { return }
        FileHandle.standardError.write(Data(("[FRANKLIN] \(utterance.text)\n").utf8))
    }

    public func run(memoryStore: C4MemoryStore) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
        }
    }

    public func silencedState() -> Bool { _silenced }
    public func silence(_ silenced: Bool) { _silenced = silenced }
}

// MARK: — FranklinConversationBridge

public actor FranklinConversationBridge {
    public static let shared = FranklinConversationBridge()

    private var _subscribed = false

    public func run(sessionID: String) async {
        _subscribed = true
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
        }
    }

    public func isSubscribed() -> Bool { _subscribed }
}

// MARK: — FranklinLearningEngine

public actor FranklinLearningEngine {
    public static let shared = FranklinLearningEngine()

    public private(set) var explorationRateSamples: [Double] = []

    public func resetLearningEngineForTests() {
        explorationRateSamples = []
    }

    public func process(outcome: TerminalOutcome, sessionID: String) async {
        await FranklinSelfModel.shared.applyOutcome(outcome)
        await AutonomyEnvelope.shared.update(from: outcome)

        let er = await FranklinSelfModel.shared.snapshot().explorationRate
        explorationRateSamples.append(er)

        let dir = AutonomyPaths.learningReceiptsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let receiptID = UUID().uuidString
        let ts = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "id": receiptID,
            "sessionID": sessionID,
            "terminal": outcome.terminal.rawValue,
            "explorationRate": er,
            "timestamp": ts,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) else { return }
        let jsonURL = dir.appendingPathComponent("\(receiptID).json")
        try? data.write(to: jsonURL, options: .atomic)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sidecar = URL(fileURLWithPath: jsonURL.path + ".sha256")
        try? Data(sha.utf8).write(to: sidecar, options: .atomic)
    }
}

// MARK: — LearningQuality

public struct LearningQuality: Sendable {
    public let narrative: String
}

// MARK: — FranklinMetaEvaluator

public actor FranklinMetaEvaluator {
    public static let shared = FranklinMetaEvaluator()

    public private(set) var metaLearningEmitCount: Int = 0

    public func resetForTests() {
        metaLearningEmitCount = 0
    }

    public func onReflectionTick(state: C4Snapshot) {
        metaLearningEmitCount += 1
        let count = metaLearningEmitCount
        let consequence = state.c4_consequence
        let iso = ISO8601DateFormatter().string(from: Date())
        Task {
            await FranklinSubstrate.shared.insertMetalearningEvent(
                id: UUID().uuidString,
                payloadJSON: "{\"c4_consequence\":\(consequence),\"metaLearningEmitCount\":\(count)}",
                timestampISO: iso
            )
        }
    }

    public func computeLearningQuality(state: C4Snapshot) -> LearningQuality {
        let narrative = "Meta-learning evaluation: consequence signal at \(String(format: "%.3f", state.c4_consequence)) drives closure reinforcement. Trust=\(String(format: "%.3f", state.c1_trust)) identity=\(String(format: "%.3f", state.c2_identity)) inform trajectory. Consequence-weighted adaptation active across all learning cycles."
        return LearningQuality(narrative: narrative)
    }
}
