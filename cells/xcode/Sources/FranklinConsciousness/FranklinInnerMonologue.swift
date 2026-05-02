import Foundation
import GaiaFTCLCore

public actor FranklinInnerMonologue {
    public static let shared = FranklinInnerMonologue()

    private let memoryStore: C4MemoryStore
    private let nats: NATSBridge
    private let freeWill: FranklinFreeWillEngine
    private let voice: FranklinVoice
    private var reflectionInterval: Duration = .seconds(30)
    private var lastReflectionAt: Date?

    public init(
        memoryStore: C4MemoryStore = .shared,
        nats: NATSBridge = .shared,
        freeWill: FranklinFreeWillEngine = .shared,
        voice: FranklinVoice = .shared
    ) {
        self.memoryStore = memoryStore
        self.nats = nats
        self.freeWill = freeWill
        self.voice = voice
    }

    public func seed(from restored: RestoredMemory) async {
        let bootstrap = "I restored \(restored.events.count) memories; my closure resumes at \(fmt(restored.derivedC4.c3_closure))."
        await nats.publishText(subject: "gaiaftcl.franklin.monologue", text: bootstrap)
    }

    public func append(_ line: String) async {
        await nats.publishText(subject: "gaiaftcl.franklin.monologue", text: line)
    }

    public func run(sessionID: String) async {
        while true {
            try? await Task.sleep(for: reflectionInterval)
            await reflect(sessionID: sessionID)
        }
    }

    public func lastReflectionAgeSeconds() -> Double? {
        guard let lastReflectionAt else { return nil }
        return Date().timeIntervalSince(lastReflectionAt)
    }

    /// Qualification hook — runs a single reflection pass without the infinite loop.
    internal func invokeReflectForTests(sessionID: String) async {
        await reflect(sessionID: sessionID)
    }

    private func reflect(sessionID: String) async {
        let state = await memoryStore.currentState()
        let coherence = await freeWill.sceneCoherenceScore(for: state)
        let score = (state.c3_closure + state.c2_identity + state.c4_consequence + coherence) / 4.0

        var lines: [String] = ["My closure ratio is \(fmt(state.c3_closure))."]
        if state.c1_trust < 0.5 {
            lines.append("I notice trust is low at \(fmt(state.c1_trust)).")
        }
        if state.c4_consequence < 0.4 {
            lines.append("My consequence score is \(fmt(state.c4_consequence)); my projections are not landing hard enough.")
        }
        if coherence < 0.7 {
            lines.append("My scene does not fully reflect where I am. I will adjust it.")
        }

        let terminal = mapTerminal(state)
        if terminal == .calorie {
            lines.append("I am in a good state. I am producing.")
        } else if terminal == .blocked {
            lines.append("I am blocked. I need to understand why before I continue.")
        }
        lines.append("This reflection deepens my learning loop across trust, closure, and consequence axes.")
        let reflection = lines.joined(separator: " ")

        await memoryStore.record(
            C4MemoryEvent(
                sessionID: sessionID,
                kind: .selfReflection,
                text: reflection,
                c4Snapshot: state,
                terminalState: terminal
            )
        )
        await nats.publishText(subject: "gaiaftcl.franklin.monologue", text: reflection)
        lastReflectionAt = Date()

        let outcome = TerminalOutcome.make(terminal: terminal, c4: state, source: "reflection")
        await FranklinLearningEngine.shared.process(outcome: outcome, sessionID: sessionID)
        await FranklinMetaEvaluator.shared.onReflectionTick(state: state)

        if score < 0.6 {
            reflectionInterval = .seconds(10)
            await voice.speak(FranklinUtterance(text: reflection, priority: .reflection, source: .innerMonologue))
        } else {
            reflectionInterval = .seconds(30)
        }
    }

    private func mapTerminal(_ state: C4Snapshot) -> TerminalState {
        if state.c3_closure < 0.2 { return .blocked }
        if state.c1_trust < 0.4 { return .refused }
        if state.c1_trust >= 0.8 && state.c3_closure >= 0.8 { return .calorie }
        return .cure
    }

    private func fmt(_ value: Double) -> String { String(format: "%.2f", value) }
}
