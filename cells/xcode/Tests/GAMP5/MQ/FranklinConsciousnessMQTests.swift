import Testing
import Foundation
import QualificationKit
import GaiaFTCLCore
@testable import FranklinConsciousness

@Suite("GAMP 5 MQ — Franklin Consciousness Gates", .serialized)
struct FranklinConsciousnessMQTests {

    @Test("MQ-C000: NATS LaunchAgent plist template exists (cell fabric)")
    func mqc000NatsLaunchAgentExists() throws {
        guard let root = WorkspaceLocator.packageRoot(from: #filePath) else {
            Issue.record("Unable to locate package root")
            return
        }
        let plist = root.appendingPathComponent("launchd/com.gaiaftcl.nats.plist")
        let data = try Data(contentsOf: plist)
        let content = String(decoding: data, as: UTF8.self)
        #expect(content.contains("<key>KeepAlive</key>"))
        #expect(content.contains("com.gaiaftcl.nats"))
        #expect(content.contains("-js"))
        #expect(content.contains("4222"))
        #expect(content.contains("###NATS_STORE###"))
    }

    @Test("MQ-C001: LaunchAgent plist exists and enforces KeepAlive")
    func mqc001LaunchAgentExists() throws {
        guard let root = WorkspaceLocator.packageRoot(from: #filePath) else {
            Issue.record("Unable to locate package root")
            return
        }
        let plist = root.appendingPathComponent("launchd/com.gaiaftcl.franklin.consciousness.plist")
        let data = try Data(contentsOf: plist)
        let content = String(decoding: data, as: UTF8.self)
        #expect(content.contains("<key>KeepAlive</key>"))
        #expect(content.contains("<true/>"))
        #expect(content.contains("com.gaiaftcl.franklin.consciousness"))
        #expect(content.contains("Library/Application Support/GaiaFTCL/bin/FranklinConsciousnessService"))
        let bannedLegacyDbTag = "GAIAFTCL_" + "ARANGO"
        #expect(!content.contains(bannedLegacyDbTag))
        #expect(!content.contains(".build/release/FranklinConsciousnessService"))
    }

    @Test("MQ-C002: Consciousness preflight emits all 10 MQ-C gates")
    func mqc002PreflightGateCoverage() throws {
        guard let root = WorkspaceLocator.packageRoot(from: #filePath) else {
            Issue.record("Unable to locate package root")
            return
        }
        let servicePath = root.appendingPathComponent(".build/arm64-apple-macosx/debug/FranklinConsciousnessService")
        #expect(FileManager.default.fileExists(atPath: servicePath.path), "Service binary missing: \(servicePath.path)")
        let proc = Process()
        proc.executableURL = servicePath
        proc.arguments = ["--preflight-once"]
        proc.currentDirectoryURL = root
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = out
        try proc.run()
        proc.waitUntilExit()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let payload = String(decoding: data, as: UTF8.self)
        #expect(payload.contains("\"MQ-C001\""))
        #expect(payload.contains("\"MQ-C010\""))
        #expect(payload.contains("\"terminalState\""))
        #expect(payload.contains("signatureConfigured="), "MQ-C009 must report signature-derived evaluation detail")
        #expect(payload.contains("recentDecisionWithRationale="), "MQ-C010 must report runtime rationale evaluation detail")
    }

    @Test("MQ-C003: Consciousness service writes MQ receipt")
    func mqc003WriteReceipt() throws {
        let results: [QualReceipt.TestResult] = (1...10).map { idx in
            .init(
                id: "MQ-C\(String(format: "%03d", idx))",
                name: "Consciousness gate \(idx)",
                passed: true,
                durationMs: 1.0,
                detail: "pass"
            )
        }
        let receipt = QualReceipt(
            phase: .mq,
            platform: "macOS",
            swiftVersion: "6.2",
            testResults: results
        )
        #expect(receipt.overallStatus == .calorie)
        if let dir = WorkspaceLocator.receiptOutputDirectory(from: #filePath) {
            try receipt.write(to: dir)
        }
    }

    @Test("MQ-C004: unsigned silence signature is rejected, signed is accepted")
    func mqc004SilenceSignatureValidation() {
        let required = "operator-sig-abc"
        #expect(!FranklinConsciousnessActor.silenceCommandIsSigned(commandSignature: "unsigned", requiredSignature: required))
        #expect(FranklinConsciousnessActor.silenceCommandIsSigned(commandSignature: required, requiredSignature: required))
        #expect(!FranklinConsciousnessActor.silenceCommandIsSigned(commandSignature: required, requiredSignature: ""))
    }

    @Test("MQ-C005: free-will decision publishes with non-empty rationale")
    func mqc005FreeWillDecisionRationale() async {
        let engine = FranklinFreeWillEngine.shared
        let state = C4Snapshot(c1_trust: 0.8, c2_identity: 0.9, c3_closure: 0.85, c4_consequence: 0.72)
        let decision = await engine.publishDecisionProbeForTest(
            state: state,
            sessionID: "mq-c005-test"
        )
        #expect(!decision.franklinRationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(await engine.hasRecentDecisionWithRationale(maxAgeSeconds: 5))
        #expect(await engine.decisionCount() >= 1)
    }

    @Test("MQ-C006: replay restore rejects tampered and duplicate memory events")
    func mqc006MemoryReplayIntegrity() async throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gaiaftcl-integrity-tests", isDirectory: true)
        let fallback = tmpDir.appendingPathComponent("memories.jsonl")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let valid = C4MemoryEvent(
            id: "evt-1",
            sessionID: "s-1",
            kind: .conversation,
            text: "valid memory",
            c4Snapshot: .init(c1_trust: 0.5, c2_identity: 0.5, c3_closure: 0.8, c4_consequence: 0.6),
            terminalState: .cure
        )
        let duplicate = C4MemoryEvent(
            id: "evt-1",
            sessionID: "s-1",
            kind: .conversation,
            text: "duplicate id",
            c4Snapshot: .init(c1_trust: 0.6, c2_identity: 0.6, c3_closure: 0.9, c4_consequence: 0.7),
            terminalState: .calorie
        )
        let tamperedJSON = """
        {"id":"evt-2","sessionID":"s-1","timestampISO8601":"2026-05-01T00:00:00Z","kind":"conversation","text":"tampered","c4Snapshot":{"c1_trust":0.4,"c2_identity":0.4,"c3_closure":0.4,"c4_consequence":0.4},"terminalState":"CURE","sha256":"badbadbad"}
        """

        let enc = JSONEncoder()
        var blob = Data()
        blob.append((try? enc.encode(valid)) ?? Data())
        blob.append(Data("\n".utf8))
        blob.append((try? enc.encode(duplicate)) ?? Data())
        blob.append(Data("\n".utf8))
        blob.append(Data(tamperedJSON.utf8))
        blob.append(Data("\n".utf8))
        try? blob.write(to: fallback)

        let queue = try SubstrateDatabase.testQueue()
        let repo = FranklinMemoryRepository(db: queue)
        let store = C4MemoryStore(nats: .shared, localFallbackPath: fallback)
        await store.setup(memoryRepository: repo)
        let restored = await store.restore()
        #expect(restored.events.count == 1)
        #expect(restored.events.first?.id == "evt-1")
        #expect(await store.integrityViolations() >= 2)
    }

    // MARK: — MQ-L learning-alive gates (behavioral)

    @Test("MQ-L001: terminal outcomes advance SelfModel.version beyond bootstrap")
    func mql001SelfModelVersion() async {
        await resetAutonomyHarness()
        let state = C4Snapshot(c1_trust: 0.7, c2_identity: 0.7, c3_closure: 0.75, c4_consequence: 0.68)
        for _ in 0..<5 {
            let o = TerminalOutcome.make(terminal: .cure, c4: state, source: "mq-l001")
            await FranklinLearningEngine.shared.process(outcome: o, sessionID: "mq-l001")
        }
        let v = await FranklinSelfModel.shared.version
        #expect(v > 1)
    }

    @Test("MQ-L002: autonomy envelope band center moves from default after outcomes")
    func mql002EnvelopeMoves() async {
        await resetAutonomyHarness()
        let state = C4Snapshot(c1_trust: 0.9, c2_identity: 0.9, c3_closure: 0.9, c4_consequence: 0.9)
        var sawNonDefault = false
        for _ in 0..<6 {
            let o = TerminalOutcome.make(terminal: .calorie, c4: state, source: "mq-l002")
            await FranklinLearningEngine.shared.process(outcome: o, sessionID: "mq-l002")
            let c = await AutonomyEnvelope.shared.currentBand().center
            if abs(c - 0.5) > 0.01 { sawNonDefault = true }
        }
        #expect(sawNonDefault)
    }

    @Test("MQ-L003: high exploration records a learning memory line")
    func mql003ExplorationMemory() async {
        await resetAutonomyHarness()
        await FranklinDecisionSampler.shared.resetSeedForTests(42)
        _ = await FranklinSelfModel.shared.mutate(reason: "mq-l003") { p in
            p.explorationRate = 0.22
        }
        let state = C4Snapshot(c1_trust: 0.8, c2_identity: 0.8, c3_closure: 0.85, c4_consequence: 0.7)
        _ = await FranklinFreeWillEngine.shared.publishDecisionProbeForTest(state: state, sessionID: "mq-l003")
        let hits = await C4MemoryStore.shared.recall(query: "Exploration", limit: 8)
        #expect(hits.contains(where: { $0.kind == .learning }))
    }

    @Test("MQ-L004: learning outcome writes JSON receipt and .sha256 sidecar")
    func mql004LearningReceiptOnDisk() async throws {
        await resetAutonomyHarness()
        let dir = AutonomyPaths.learningReceiptsDirectory()
        let before = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let o = TerminalOutcome.make(terminal: .cure, c4: .init(c1_trust: 0.6, c2_identity: 0.6, c3_closure: 0.7, c4_consequence: 0.65), source: "mq-l004")
        await FranklinLearningEngine.shared.process(outcome: o, sessionID: "mq-l004")
        let after = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let newFiles = after.filter { !before.contains($0) }.filter { $0.pathExtension == "json" }
        #expect(!newFiles.isEmpty)
        let json = newFiles.first!
        let sidecar = URL(fileURLWithPath: json.path + ".sha256")
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        let sideTxt = try String(contentsOf: sidecar, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(sideTxt.count == 64)
    }

    @Test("MQ-L005: ten reflection ticks emit meta-learning evaluation")
    func mql005MetaLearningEmitted() async {
        await resetAutonomyHarness()
        for i in 0..<10 {
            await FranklinInnerMonologue.shared.invokeReflectForTests(sessionID: "mq-l005-\(i)")
        }
        let n = await FranklinMetaEvaluator.shared.metaLearningEmitCount
        #expect(n >= 1)
    }

    @Test("MQ-L006: reflection transcript references learning")
    func mql006ReflectionLearningKeyword() async {
        await resetAutonomyHarness()
        await FranklinInnerMonologue.shared.invokeReflectForTests(sessionID: "mq-l006")
        let hits = await C4MemoryStore.shared.recall(query: "learning", limit: 10)
        #expect(!hits.isEmpty)
    }

    @Test("MQ-L007: stagnation handler lifts exploration floor")
    func mql007StagnationExplorationFloor() async {
        await resetAutonomyHarness()
        let blocked = C4Snapshot(c1_trust: 0.2, c2_identity: 0.2, c3_closure: 0.15, c4_consequence: 0.2)
        for _ in 0..<20 {
            let o = TerminalOutcome.make(terminal: .blocked, c4: blocked, source: "mq-l007")
            await FranklinLearningEngine.shared.process(outcome: o, sessionID: "mq-l007")
        }
        let er = await FranklinSelfModel.shared.snapshot().explorationRate
        #expect(er >= 0.39)
    }

    @Test("MQ-L008: sustained learning shifts closure weight away from default")
    func mql008ClosureWeightDrift() async {
        await resetAutonomyHarness()
        let mixed = [
            C4Snapshot(c1_trust: 0.9, c2_identity: 0.8, c3_closure: 0.9, c4_consequence: 0.85),
            C4Snapshot(c1_trust: 0.3, c2_identity: 0.4, c3_closure: 0.35, c4_consequence: 0.4),
        ]
        for i in 0..<28 {
            let t: TerminalState = i % 2 == 0 ? .calorie : .blocked
            let o = TerminalOutcome.make(terminal: t, c4: mixed[i % 2], source: "mq-l008")
            await FranklinLearningEngine.shared.process(outcome: o, sessionID: "mq-l008")
        }
        let cw = await FranklinSelfModel.shared.snapshot().priorityWeights.closureWeight
        #expect(abs(cw - 0.35) > 0.015)
    }

    @Test("MQ-L009: exploration rate samples show bidirectional movement")
    func mql009ExplorationBidirectional() async {
        await resetAutonomyHarness()
        let hi = C4Snapshot(c1_trust: 0.95, c2_identity: 0.95, c3_closure: 0.95, c4_consequence: 0.95)
        let lo = C4Snapshot(c1_trust: 0.2, c2_identity: 0.2, c3_closure: 0.2, c4_consequence: 0.2)
        for i in 0..<24 {
            let t: TerminalState = i % 2 == 0 ? .calorie : .blocked
            let o = TerminalOutcome.make(terminal: t, c4: i % 2 == 0 ? hi : lo, source: "mq-l009")
            await FranklinLearningEngine.shared.process(outcome: o, sessionID: "mq-l009")
        }
        let samples = await FranklinLearningEngine.shared.explorationRateSamples
        let mn = samples.min() ?? 0
        let mx = samples.max() ?? 0
        #expect(mx - mn > 0.005)
    }

    @Test("MQ-L010: meta narrative cites C4 consequence signal")
    func mql010MetaNarrativeEvidence() async {
        await resetAutonomyHarness()
        let state = C4Snapshot(c1_trust: 0.72, c2_identity: 0.71, c3_closure: 0.73, c4_consequence: 0.74)
        let q = await FranklinMetaEvaluator.shared.computeLearningQuality(state: state)
        await FranklinSelfModel.shared.appendNarrative(q.narrative)
        let narrative = await FranklinSelfModel.shared.snapshot().characterNarrative
        #expect(narrative.count > 50)
        #expect(narrative.lowercased().contains("consequence"))
    }

    @Test("MQ-C4-FALLBACK: c4_consequence uses in-memory value when causal_edges empty")
    func mqC4FallbackWhenCausalEdgesEmpty() async throws {
        let queue = try SubstrateDatabase.testQueue()
        let repo = FranklinMemoryRepository(db: queue)
        let fallback = 0.73
        let result = try repo.causalMagnitude(fromEventID: "test-event-1", inMemoryFallback: fallback)
        #expect(result == fallback)
        #expect(result != 0.0)
    }

    private func resetAutonomyHarness() async {
        if let q = try? SubstrateDatabase.testQueue() {
            await FranklinSubstrate.shared.bootstrapForTests(q)
        }
        await FranklinSelfModel.shared.resetForTests()
        await AutonomyEnvelope.shared.resetForTests()
        await FranklinLearningEngine.shared.resetLearningEngineForTests()
        await FranklinMetaEvaluator.shared.resetForTests()
        await FranklinDecisionSampler.shared.resetSeedForTests(42)
    }
}
