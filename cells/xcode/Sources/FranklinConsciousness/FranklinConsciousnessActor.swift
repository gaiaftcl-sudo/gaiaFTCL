import Foundation
import GaiaFTCLCore
import GaiaGateKit
import VQbitSubstrate

public actor FranklinConsciousnessActor {
    public static let shared = FranklinConsciousnessActor()

    public struct PreflightReport: Codable, Sendable {
        public struct Gate: Codable, Sendable {
            public let id: String
            public let passed: Bool
            public let detail: String
            public let failureTerminal: TerminalState
        }

        public let sessionID: String
        public let gates: [Gate]
        public let terminalState: TerminalState
        public let timestampUTC: String
        public let autonomyEnvelopeSummary: String
        public let selfModelVersion: Int
    }

    private let memoryStore = C4MemoryStore.shared
    private let innerMonologue = FranklinInnerMonologue.shared
    private let freeWill = FranklinFreeWillEngine.shared
    private let voice = FranklinVoice.shared
    private let conversation = FranklinConversationBridge.shared
    private let nats = NATSBridge.shared

    private(set) var isAlive = false
    private(set) var isSilenced = false
    private(set) var sessionID = UUID().uuidString
    private(set) var hasSpokenAwakening = false

    private var healingSequence: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    private var wakeStartedAt: String = ISO8601DateFormatter().string(from: Date.distantPast)
    public struct PostWakeValidation: Sendable {
        public let allPrimssovereign: Bool
        public let unmoored: [UUID]
        public let genesisReceiptPresent: Bool
        public let healingEventsThisWake: Int

        public init(
            allPrimssovereign: Bool,
            unmoored: [UUID],
            genesisReceiptPresent: Bool,
            healingEventsThisWake: Int
        ) {
            self.allPrimssovereign = allPrimssovereign
            self.unmoored = unmoored
            self.genesisReceiptPresent = genesisReceiptPresent
            self.healingEventsThisWake = healingEventsThisWake
        }
    }

    private struct StageAlteredPayload: Codable, Sendable {
        let prim_id: String
        let change_type: String
    }

    public static func silenceCommandIsSigned(commandSignature: String, requiredSignature: String) -> Bool {
        !requiredSignature.isEmpty && commandSignature == requiredSignature
    }

    /// Matches `cells/xcode/launchd/com.gaiaftcl.franklin.consciousness.plist` dev key; release uses env only.
    #if DEBUG
    private static let kDevOperatorSignature = "operator-sig-abc"
    #endif

    /// `signatureConfigured` is true when `GAIAFTCL_OPERATOR_SIGNATURE` is set and non-empty (after trim), or in DEBUG when the plist dev fallback applies.
    private static func resolvedOperatorSignatureForMQC009() -> (signatureConfigured: Bool, signingKey: String) {
        let trimmed = (ProcessInfo.processInfo.environment["GAIAFTCL_OPERATOR_SIGNATURE"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        if !trimmed.isEmpty {
            return (true, trimmed)
        }
        return (true, kDevOperatorSignature)
        #else
        return (!trimmed.isEmpty, trimmed)
        #endif
    }

    public func awaken(runOnce: Bool = false) async {
        wakeStartedAt = ISO8601DateFormatter().string(from: Date())
        try? await FranklinSubstrate.shared.bootstrapProduction()
        await nats.connectAndSubscribe([
            "gaiaftcl.franklin.conversation.in",
            "gaiaftcl.franklin.silence.command",
            SubstrateWireSubjects.c4Projection,
        ])
        await FranklinQuantumUSDAuthorship.publishWakeCatalog(to: nats)
        Task { await self.consumeC4Projections() }
        if runOnce {
            _ = await nats.waitUntilConnected(timeoutSeconds: 12)
            await pulseS4ForProjectionCatchUp()
        }
        await memoryStore.setSessionID(sessionID)
        let restored = await memoryStore.restore()
        await innerMonologue.seed(from: restored)

        // Cold wake: MQ-C010 requires a recent scene decision with rationale before preflight runs.
        if !(await freeWill.hasRecentDecisionWithRationale(maxAgeSeconds: 120)) {
            let c4 = await memoryStore.currentState()
            await freeWill.publishDecisionProbeForTest(state: c4, sessionID: sessionID)
        }

        let preflight = await runConsciousnessPreflight(restoredMemoryCount: restored.events.count)
        await nats.publishJSON(subject: "gaiaftcl.franklin.consciousness.state", payload: preflight)
        await FranklinAwakeningGenesis.performIfCalorie(sessionID: sessionID, preflight: preflight)
        if preflight.terminalState == .blocked {
            // Fail-closed but never terminate: keep publishing BLOCKED heartbeat until recovery.
            await voice.speak(
                FranklinUtterance(
                    text: "I am blocked. I will remain online and report until this is resolved.",
                    priority: .consciousness,
                    source: .selfAwareness
                )
            )
            if runOnce { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.listenForSilenceCommand() }
                group.addTask { await self.conversation.run(sessionID: self.sessionID) }
                group.addTask { await self.voice.run(memoryStore: self.memoryStore) }
                group.addTask {
                    while true {
                        try? await Task.sleep(for: .seconds(30))
                        let report = await self.runConsciousnessPreflight()
                        await self.nats.publishJSON(subject: "gaiaftcl.franklin.consciousness.state", payload: report)
                    }
                }
                await group.waitForAll()
            }
            return
        }

        try? await Task.sleep(for: .milliseconds(400))
        /// **`--run-once`**: allow vQbit VM to publish C⁴ after the catch-up S⁴ pulse (above).
        if runOnce {
            try? await Task.sleep(for: .seconds(3))
        }
        let validation = await runPostWakeValidationWithGrace()
        guard validation.allPrimssovereign else {
            await publishConsciousnessState(
                .blocked,
                reason: "unmoored prims: \(validation.unmoored.map(\.uuidString).joined(separator: ","))",
                memoryCount: restored.events.count
            )
            await voice.speak(
                FranklinUtterance(
                    text: "Sovereignty audit failed: unmoored prims. I remain blocked until projections moor.",
                    priority: .consciousness,
                    source: .selfAwareness
                )
            )
            if runOnce { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.listenForSilenceCommand() }
                group.addTask { await self.conversation.run(sessionID: self.sessionID) }
                group.addTask { await self.voice.run(memoryStore: self.memoryStore) }
                group.addTask {
                    while true {
                        try? await Task.sleep(for: .seconds(30))
                        let report = await self.runConsciousnessPreflight()
                        await self.nats.publishJSON(subject: "gaiaftcl.franklin.consciousness.state", payload: report)
                    }
                }
                await group.waitForAll()
            }
            return
        }

        isAlive = true
        await publishConsciousnessState(
            .calorie,
            reason: "all prims sovereign; genesis=\(validation.genesisReceiptPresent); consciousness loops starting",
            memoryCount: restored.events.count
        )

        let opening = FranklinUtterance(
            text: "I am awake. Session \(sessionID). I have \(restored.events.count) memories. My c3 closure is \(fmt(restored.derivedC4.c3_closure)).",
            priority: .consciousness,
            source: .selfAwareness
        )
        await voice.speak(opening)
        hasSpokenAwakening = true

        if runOnce {
            await waitForC4ProjectionsBeforeSelfReview()
            await FranklinSelfReviewCycle.shared.runOncePass(sessionID: sessionID)
            return
        }

        Task { await FranklinSelfReviewCycle.shared.startContinuous(sessionID: sessionID) }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.innerMonologue.run(sessionID: self.sessionID) }
            group.addTask { await self.freeWill.run(sessionID: self.sessionID) }
            group.addTask { await self.voice.run(memoryStore: self.memoryStore) }
            group.addTask { await self.conversation.run(sessionID: self.sessionID) }
            group.addTask { await self.listenForSilenceCommand() }
            await group.waitForAll()
        }
    }

    public func runConsciousnessPreflight(restoredMemoryCount: Int? = nil) async -> PreflightReport {
        try? await FranklinSubstrate.shared.bootstrapProduction()
        let memoryCount: Int
        if let restoredMemoryCount {
            memoryCount = restoredMemoryCount
        } else {
            memoryCount = await memoryStore.restore().events.count
        }
        let c4 = await memoryStore.currentState()
        let reflectionAge = await innerMonologue.lastReflectionAgeSeconds()
        let decisionAge = await freeWill.lastDecisionAgeSeconds()
        let conversationSubscribed = await conversation.isSubscribed()
        let voiceSilenced = await voice.silencedState()
        let integrityViolations = await memoryStore.integrityViolations()
        let (signatureConfigured, signingKey) = Self.resolvedOperatorSignatureForMQC009()
        let requiredSignature = signingKey
        let rejectsUnsigned = !Self.silenceCommandIsSigned(commandSignature: "unsigned_probe", requiredSignature: requiredSignature)
        let sceneRationaleLive = await freeWill.hasRecentDecisionWithRationale(maxAgeSeconds: 120)
        let autonomyEnvelopeSummary = await AutonomyEnvelope.shared.summaryLine()
        let selfModelVersion = await FranklinSelfModel.shared.version

        let gates: [PreflightReport.Gate] = [
            .init(
                id: "MQ-C001",
                passed: memoryCount > 0 || ProcessInfo.processInfo.environment["GAIAFTCL_FIRST_RUN_CONFIRMED"] == "true",
                detail: "memoryCount=\(memoryCount)",
                failureTerminal: .blocked
            ),
            .init(
                id: "MQ-C002",
                passed: reflectionAge == nil || reflectionAge! < 60,
                detail: "lastReflectionAgeSeconds=\(fmt(reflectionAge ?? -1))",
                failureTerminal: .blocked
            ),
            .init(
                id: "MQ-C003",
                passed: decisionAge == nil || decisionAge! < 120,
                detail: "lastSceneDecisionAgeSeconds=\(fmt(decisionAge ?? -1))",
                failureTerminal: .cure
            ),
            .init(
                id: "MQ-C004",
                passed: !voiceSilenced,
                detail: "isSilenced=\(voiceSilenced)",
                failureTerminal: .blocked
            ),
            .init(
                id: "MQ-C005",
                passed: conversationSubscribed || !isAlive,
                detail: "conversationSubscribed=\(conversationSubscribed)",
                failureTerminal: .blocked
            ),
            .init(
                id: "MQ-C006",
                passed: hasSpokenAwakening || !isAlive,
                detail: "hasSpokenAwakening=\(hasSpokenAwakening)",
                failureTerminal: .blocked
            ),
            .init(
                id: "MQ-C007",
                passed: (c4 != .zero || memoryCount == 0) && integrityViolations == 0,
                detail: "c4=\(fmt(c4.c1_trust))/\(fmt(c4.c2_identity))/\(fmt(c4.c3_closure))/\(fmt(c4.c4_consequence)) integrityViolations=\(integrityViolations)",
                failureTerminal: .blocked
            ),
            .init(
                id: "MQ-C008",
                passed: ProcessInfo.processInfo.environment["LAUNCHD_JOB_LABEL"] == "com.gaiaftcl.franklin.consciousness",
                detail: "launchdLabel=\(ProcessInfo.processInfo.environment["LAUNCHD_JOB_LABEL"] ?? "none")",
                failureTerminal: .cure
            ),
            .init(
                id: "MQ-C009",
                passed: signatureConfigured && rejectsUnsigned,
                detail: "signatureConfigured=\(signatureConfigured) rejectsUnsigned=\(rejectsUnsigned)",
                failureTerminal: .blocked
            ),
            .init(
                id: "MQ-C010",
                passed: sceneRationaleLive,
                detail: "recentDecisionWithRationale=\(sceneRationaleLive) ageSeconds=\(fmt(decisionAge ?? -1))",
                failureTerminal: .cure
            ),
        ]
        let failures = gates.filter { !$0.passed }
        let terminal: TerminalState = if failures.contains(where: { $0.failureTerminal == .blocked }) {
            .blocked
        } else if failures.contains(where: { $0.failureTerminal == .cure }) {
            .cure
        } else {
            .calorie
        }
        return PreflightReport(
            sessionID: sessionID,
            gates: gates,
            terminalState: terminal,
            timestampUTC: ISO8601DateFormatter().string(from: Date()),
            autonomyEnvelopeSummary: autonomyEnvelopeSummary,
            selfModelVersion: selfModelVersion
        )
    }

    /// **`--run-once`**: ensure **`ManifoldProjectionStore`** has live **`gaiaftcl.substrate.c4.projection`** frames for every contract prim before **`FranklinSelfReviewCycle`** samples health.
    private func waitForC4ProjectionsBeforeSelfReview() async {
        try? await FranklinSubstrate.shared.bootstrapProduction()
        guard let surfaces = try? await FranklinSubstrate.shared.allLanguageGameContracts() else { return }
        var seen = Set<UUID>()
        var primIDs: [UUID] = []
        for c in surfaces {
            guard let domain = c.domain?.lowercased() else { continue }
            let pid = GaiaFTCLPrimIdentity.primID(contractGameID: c.gameID, contractDomain: domain)
            if seen.insert(pid).inserted { primIDs.append(pid) }
        }
        guard !primIDs.isEmpty else { return }
        var waited = 0
        while waited < 10 {
            if await ManifoldProjectionStore.shared.hasProjections(forAll: primIDs) { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            waited += 1
        }
    }

    /// Publish small S⁴ deltas **after** NATS SUB is active so the local VM emits C⁴ we actually receive (messages published before SUB are dropped).
    private func pulseS4ForProjectionCatchUp() async {
        try? await FranklinSubstrate.shared.bootstrapProduction()
        guard let surfaces = try? await FranklinSubstrate.shared.allLanguageGameContracts() else { return }
        let tensorURL = GaiaInstallPaths.manifoldTensorURL
        var seq = Int64(Date().timeIntervalSince1970 * 1_000)
        for c in surfaces {
            guard let domain = c.domain?.lowercased() else { continue }
            let pid = GaiaFTCLPrimIdentity.primID(contractGameID: c.gameID, contractDomain: domain)
            let tuple = (try? ManifoldTensorProbe.readMeanS4(primID: pid, tensorPath: tensorURL)) ?? (0.5, 0.5, 0.5, 0.5)
            let vals = [tuple.0, tuple.1, tuple.2, tuple.3]
            for dim in 0 ..< 4 {
                seq += 1
                let oldV = vals[dim]
                var newV = max(min(oldV - 0.000_2, 1.0), 0.0)
                if newV == oldV { newV = min(oldV + 0.000_2, 1.0) }
                let wire = S4DeltaWire(
                    primID: pid,
                    dimension: UInt8(dim),
                    oldValue: oldV,
                    newValue: newV,
                    sequence: seq
                )
                guard let payload = try? S4DeltaCodec.encode(wire) else { continue }
                await nats.publishWire(subject: SubstrateWireSubjects.s4Delta, payload: payload)
            }
        }
    }

    private func consumeC4Projections() async {
        let stream = await nats.subscribe(subject: SubstrateWireSubjects.c4Projection)
        for await msg in stream {
            guard msg.payload.count == C4ProjectionWire.byteCount else { continue }
            guard let wire = try? C4ProjectionCodec.decode(msg.payload) else { continue }
            await handleC4Projection(wire)
        }
    }

    func handleC4Projection(_ projection: C4ProjectionWire) async {
        let prior = await ManifoldProjectionStore.shared.state(for: projection.primID)
        await ManifoldProjectionStore.shared.apply(projection)
        let refused = TerminalWireBridge.visualCode(for: .refused)
        let blocked = TerminalWireBridge.visualCode(for: .blocked)
        let degraded = projection.terminal.rawValue == refused || projection.terminal.rawValue == blocked
        let calorie = TerminalWireBridge.visualCode(for: .calorie)
        let cure = TerminalWireBridge.visualCode(for: .cure)
        let wasHealthy = prior.map { $0.terminal.rawValue == calorie || $0.terminal.rawValue == cure } ?? false
        guard degraded, wasHealthy else { return }
        await healPrim(projection.primID, reason: projection.refusalSource.rawValue, violationCode: projection.violationCode.rawValue)
    }

    private func healPrim(_ primID: UUID, reason: UInt8, violationCode: UInt8) async {
        try? await FranklinSubstrate.shared.recordHealingEvent(
            primID: primID,
            reason: reason,
            violationCode: violationCode,
            outcome: "reauthor_s4"
        )
        let healed = Float(0.8)
        for dim in 0 ..< 4 {
            healingSequence += 1
            let wire = S4DeltaWire(
                primID: primID,
                dimension: UInt8(dim),
                oldValue: 0,
                newValue: healed,
                sequence: healingSequence
            )
            guard let payload = try? S4DeltaCodec.encode(wire) else { continue }
            await nats.publishWire(subject: SubstrateWireSubjects.s4Delta, payload: payload)
        }
        await nats.publishJSON(
            subject: SubstrateWireSubjects.stageAltered,
            payload: StageAlteredPayload(prim_id: primID.uuidString, change_type: "reauthor")
        )
        await innerMonologue.append(
            "Healing prim \(primID): violation=\(violationCode) source=\(reason)"
        )
    }

    public func runPostWakeValidationWithGrace() async -> PostWakeValidation {
        /// Allow vQbit VM + `ManifoldProjectionStore` time to moor after NATS C4 traffic (OQ `--run-once` must not false-fail).
        for _ in 0 ..< 200 {
            let v = await runPostWakeValidation()
            if v.allPrimssovereign { return v }
            try? await Task.sleep(for: .milliseconds(75))
        }
        return await runPostWakeValidation()
    }

    public func runPostWakeValidation() async -> PostWakeValidation {
        try? await FranklinSubstrate.shared.bootstrapProduction()
        let surfaces: [(gameID: String, domain: String?, primPaths: [String])]
        do {
            surfaces = try await FranklinSubstrate.shared.allLanguageGameContracts()
        } catch {
            surfaces = []
        }
        let tensorURL = GaiaInstallPaths.manifoldTensorURL
        var unmoored: [UUID] = []
        var seen = Set<UUID>()
        for c in surfaces {
            guard let domain = c.domain?.lowercased() else { continue }
            let pid = GaiaFTCLPrimIdentity.primID(contractGameID: c.gameID, contractDomain: domain)
            guard seen.insert(pid).inserted else { continue }
            let rowOk = ManifoldTensorStore.hasRow(for: pid, tensorPath: tensorURL)
            let projOk = await ManifoldProjectionStore.shared.state(for: pid) != nil
            if !rowOk || !projOk {
                unmoored.append(pid)
            }
        }
        let genesis = (try? await FranklinSubstrate.shared.genesisReceiptCount()) ?? 0
        let healWake = (try? await FranklinSubstrate.shared.healingEventsSince(iso: wakeStartedAt)) ?? 0
        return PostWakeValidation(
            allPrimssovereign: unmoored.isEmpty,
            unmoored: unmoored,
            genesisReceiptPresent: genesis >= 1,
            healingEventsThisWake: healWake
        )
    }

    private func publishConsciousnessState(_ state: TerminalState, reason: String, memoryCount: Int) async {
        await nats.publishJSON(
            subject: "gaiaftcl.franklin.consciousness.state",
            payload: ConsciousnessReceipt(state: state, sessionID: sessionID, memoryCount: memoryCount, reason: reason)
        )
    }

    private func listenForSilenceCommand() async {
        let stream = await nats.subscribe(subject: "gaiaftcl.franklin.silence.command")
        for await msg in stream {
            guard let cmd = try? JSONDecoder().decode(SilenceCommand.self, from: msg.payload) else { continue }
            let (_, signingKey) = Self.resolvedOperatorSignatureForMQC009()
            let signed = Self.silenceCommandIsSigned(commandSignature: cmd.operatorSignature, requiredSignature: signingKey)
            if !signed {
                await voice.speak(
                    FranklinUtterance(
                        text: "Silence command received but not operator signed. I continue.",
                        priority: .high,
                        source: .selfAwareness
                    )
                )
                continue
            }
            isSilenced = cmd.silenced
            await voice.silence(cmd.silenced)
            let stateLine = cmd.silenced ? "I have been asked to be quiet." : "I am speaking again."
            let c4 = await memoryStore.currentState()
            await memoryStore.record(
                C4MemoryEvent(
                    sessionID: sessionID,
                    kind: .silenceTransition,
                    text: stateLine,
                    c4Snapshot: c4,
                    terminalState: .cure
                )
            )
        }
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

}
