import Foundation
import GaiaFTCLCore
import GaiaGateKit
import VQbitSubstrate

public protocol SovereigntyProvider: Sendable {
    func validate() async -> FranklinConsciousnessActor.PostWakeValidation
}

/// Production sovereignty gate (`FranklinConsciousnessActor.postWakeValidation`).
public struct LiveSovereigntyProvider: SovereigntyProvider {
    public init() {}

    public func validate() async -> FranklinConsciousnessActor.PostWakeValidation {
        await FranklinConsciousnessActor.shared.runPostWakeValidationWithGrace()
    }
}

private struct StageAlteredPayload: Codable, Sendable {
    let prim_id: String
    let change_type: String
}

/// Per-domain constitutional self-review loop (**NATS-only** side-effects — GRDB + wire — no USD calls).
public actor FranklinSelfReviewCycle {
    public static let shared = FranklinSelfReviewCycle()

    private let sovereigntyProvider: SovereigntyProvider
    /// Optional MQ harness override — defaults to live **`ManifoldProjectionStore`** sampling.
    private let healthSampler: (@Sendable (_ domain: String, _ primIDs: [UUID]) async -> Double)?
    private var s4DeltaSequence: Int64

    private init() {
        sovereigntyProvider = LiveSovereigntyProvider()
        healthSampler = nil
        s4DeltaSequence = Int64(Date().timeIntervalSince1970 * 1_000)
    }

    /// MQ harness (**`@testable`**).
    internal init(
        sovereigntyProvider: SovereigntyProvider,
        healthSampler: (@Sendable (_ domain: String, _ primIDs: [UUID]) async -> Double)?,
        initialS4Sequence: Int64 = 77
    ) {
        self.sovereigntyProvider = sovereigntyProvider
        self.healthSampler = healthSampler
        self.s4DeltaSequence = initialS4Sequence
    }

    /// One deterministic pass over each active domain (**`--run-once`** CLI path).
    public func runOncePass(sessionID: String) async {
        let validation = await sovereigntyProvider.validate()
        guard validation.allPrimssovereign else { return }
        try? await FranklinSubstrate.shared.bootstrapProduction()
        let surfaces = (try? await FranklinSubstrate.shared.allLanguageGameContracts()) ?? []
        let domains = Set(surfaces.compactMap { $0.domain?.lowercased() }).sorted()
        for domain in domains {
            await runSingleDomainCycle(domain: domain, sessionID: sessionID, surfaces: surfaces)
        }
    }

    /// Continuous background loops (**one `Task` per domain**).
    public func startContinuous(sessionID: String) async {
        let validation = await sovereigntyProvider.validate()
        guard validation.allPrimssovereign else { return }
        try? await FranklinSubstrate.shared.bootstrapProduction()
        let surfaces = (try? await FranklinSubstrate.shared.allLanguageGameContracts()) ?? []
        let domains = Set(surfaces.compactMap { $0.domain?.lowercased() }).sorted()
        for domain in domains {
            Task { [surfaces] in
                await self.domainLoop(domain: domain, sessionID: sessionID, surfaces: surfaces)
            }
        }
    }

    private func domainLoop(domain: String, sessionID: String, surfaces: [(gameID: String, domain: String?, primPaths: [String])]) async {
        while !Task.isCancelled {
            try? await FranklinSubstrate.shared.bootstrapProduction()
            guard let row = try? await FranklinSubstrate.shared.fetchActiveContractStandards(domain: domain) else {
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            let interval = max(row.reviewIntervalSeconds, 0)
            await runSingleDomainCycle(domain: domain, sessionID: sessionID, surfaces: surfaces)
            let sleepSecs = UInt64(interval > 0 ? interval : 300)
            try? await Task.sleep(for: .seconds(sleepSecs))
        }
    }

    internal func runSingleDomainCycle(
        domain: String,
        sessionID: String,
        surfaces: [(gameID: String, domain: String?, primPaths: [String])]
    ) async {
        let cycleRowID = UUID().uuidString
        let started = ISO8601DateFormatter().string(from: Date())
        try? await FranklinSubstrate.shared.bootstrapProduction()
        guard let row = try? await FranklinSubstrate.shared.fetchActiveContractStandards(domain: domain) else { return }
        guard row.constitutionalThresholdCalorie > row.constitutionalThresholdCure else {
            await FranklinInnerMonologue.shared.append(
                "Self-review \(domain): BLOCKED — constitutional thresholds invalid (calorie must exceed cure)."
            )
            return
        }
        let primIDs = Self.primIDs(forDomain: domain, surfaces: surfaces)
        guard let primForWire = primIDs.first else { return }

        let threshold = row.constitutionalThresholdCalorie
        let priorHealth = await sampleHealth(domain: domain, primIDs: primIDs)
        var receiptID: String?
        var improvedWeights = false
        if priorHealth < threshold {
            receiptID = await improveDomainStandard(
                domain: domain,
                sessionID: sessionID,
                contract: row,
                primID: primForWire,
                priorHealthScore: priorHealth,
                cycleRowID: cycleRowID
            )
            improvedWeights = receiptID != nil
        }

        let halfInterval = max(row.reviewIntervalSeconds / 2, 0)
        /// Cap so **`--run-once`** and operator shells remain bounded (full interval still configurable on contract row).
        let cappedHalf = min(halfInterval, 45)
        if cappedHalf > 0 {
            try? await Task.sleep(for: .seconds(UInt64(cappedHalf)))
        } else {
            try? await Task.sleep(for: .milliseconds(25))
        }

        let postHealth = await sampleHealth(domain: domain, primIDs: primIDs)
        let ended = ISO8601DateFormatter().string(from: Date())

        let action: String
        if improvedWeights, postHealth > priorHealth {
            action = "improved"
        } else if improvedWeights {
            action = "adjusted_no_projection_lift"
        } else {
            action = "observed"
        }

        try? await FranklinSubstrate.shared.insertFranklinReviewCycle(
            id: cycleRowID,
            domain: domain,
            cycleStartedAtISO: started,
            cycleEndedAtISO: ended,
            priorHealthScore: priorHealth,
            postHealthScore: postHealth,
            healthScore: postHealth,
            threshold: threshold,
            actionTaken: action,
            outcome: improvedWeights ? "domain_standard_bumped" : "within_threshold_or_audit",
            receiptID: receiptID
        )

        await FranklinInnerMonologue.shared.append(
            "Self-review \(domain): prior=\(fmt(priorHealth)) post=\(fmt(postHealth)) threshold=\(fmt(threshold)) action=\(action)."
        )
    }

    private func sampleHealth(domain: String, primIDs: [UUID]) async -> Double {
        if let healthSampler {
            return await healthSampler(domain, primIDs)
        }
        let tensorURL = GaiaInstallPaths.manifoldTensorURL
        var scores: [Double] = []
        for pid in primIDs {
            if let proj = await ManifoldProjectionStore.shared.state(for: pid) {
                let c1 = Double(proj.c1Trust)
                let c3 = Double(proj.c3Closure)
                let combined = (c1 + c3) / 2.0
                if c1.isFinite, c3.isFinite, combined.isFinite, combined >= 0, combined <= 1.0 {
                    scores.append(combined)
                    continue
                }
            }
            if let tuple = try? ManifoldTensorProbe.readMeanS4(primID: pid, tensorPath: tensorURL) {
                let ip = Double(tuple.0 + tuple.1 + tuple.2 + tuple.3) / 4.0
                scores.append(min(max(ip, 0), 1))
            }
        }
        guard !scores.isEmpty else { return 0 }
        let avg = scores.reduce(0, +) / Double(scores.count)
        return min(max(avg, 0), 1)
    }

    private nonisolated static func primIDs(
        forDomain domain: String,
        surfaces: [(gameID: String, domain: String?, primPaths: [String])]
    ) -> [UUID] {
        let key = domain.lowercased()
        var seen = Set<UUID>()
        var out: [UUID] = []
        for c in surfaces {
            guard let d = c.domain?.lowercased(), d == key else { continue }
            let pid = GaiaFTCLPrimIdentity.primID(contractGameID: c.gameID, contractDomain: d)
            if seen.insert(pid).inserted { out.append(pid) }
        }
        return out
    }

    /// NATS-only **`improveDomainStandard`** — GRDB + **`stage.altered`** + **`s4.delta`** (+ learning receipt).
    private func improveDomainStandard(
        domain: String,
        sessionID: String,
        contract: FranklinDocumentRepository.LanguageGameContractStandardsRow,
        primID: UUID,
        priorHealthScore: Double,
        cycleRowID: String
    ) async -> String? {
        let tensorURL = GaiaInstallPaths.manifoldTensorURL
        let weakest: Int = if ProcessInfo.processInfo.environment["GAIAFTCL_MQ_SELF_REVIEW_SKIP_TENSOR"] == "1" {
            0
        } else {
            ManifoldTensorProbe.weakestS4Dimension(primID: primID, tensorPath: tensorURL)
        }
        guard let envelope = try? AestheticRulesCodec.decode(from: contract.aestheticRulesJSON) else { return nil }

        let inc = contract.improvementTarget
        let oldWeights = envelope.weights
        let oldVal: Double = {
            switch weakest {
            case 0: oldWeights.s1_weight
            case 1: oldWeights.s2_weight
            case 2: oldWeights.s3_weight
            default: oldWeights.s4_weight
            }
        }()
        let newVal = min(oldVal + inc, 1.0)
        guard newVal > oldVal else { return nil }

        let newEnvelope: AestheticRulesEnvelope
        switch weakest {
        case 0:
            newEnvelope = AestheticRulesEnvelope(
                schema_version: envelope.schema_version,
                weights: .init(
                    s1_weight: newVal,
                    s2_weight: oldWeights.s2_weight,
                    s3_weight: oldWeights.s3_weight,
                    s4_weight: oldWeights.s4_weight
                )
            )
        case 1:
            newEnvelope = AestheticRulesEnvelope(
                schema_version: envelope.schema_version,
                weights: .init(
                    s1_weight: oldWeights.s1_weight,
                    s2_weight: newVal,
                    s3_weight: oldWeights.s3_weight,
                    s4_weight: oldWeights.s4_weight
                )
            )
        case 2:
            newEnvelope = AestheticRulesEnvelope(
                schema_version: envelope.schema_version,
                weights: .init(
                    s1_weight: oldWeights.s1_weight,
                    s2_weight: oldWeights.s2_weight,
                    s3_weight: newVal,
                    s4_weight: oldWeights.s4_weight
                )
            )
        default:
            newEnvelope = AestheticRulesEnvelope(
                schema_version: envelope.schema_version,
                weights: .init(
                    s1_weight: oldWeights.s1_weight,
                    s2_weight: oldWeights.s2_weight,
                    s3_weight: oldWeights.s3_weight,
                    s4_weight: newVal
                )
            )
        }

        guard let canonData = try? AestheticRulesCodec.canonicalJSONData(newEnvelope),
              let canonStr = String(data: canonData, encoding: .utf8)
        else { return nil }
        let shaContract = AestheticRulesCodec.sha256Hex(ofCanonicalJSON: canonData)

        try? await FranklinSubstrate.shared.updateContractAestheticRules(
            contractID: contract.id,
            aestheticRulesJSON: canonStr,
            contractSha256: shaContract
        )

        let skipWire = ProcessInfo.processInfo.environment["GAIAFTCL_MQ_SELF_REVIEW_SKIP_WIRE"] == "1"
        if !skipWire {
            await NATSBridge.shared.publishJSON(
                subject: SubstrateWireSubjects.stageAltered,
                payload: StageAlteredPayload(prim_id: primID.uuidString, change_type: "standard_improvement")
            )
        }

        let tuple: (Float, Float, Float, Float) = if ProcessInfo.processInfo.environment["GAIAFTCL_MQ_SELF_REVIEW_SKIP_TENSOR"] == "1" {
            (0.5, 0.5, 0.5, 0.5)
        } else {
            (try? ManifoldTensorProbe.readMeanS4(primID: primID, tensorPath: tensorURL)) ?? (0.5, 0.5, 0.5, 0.5)
        }
        let tensorVals = [tuple.0, tuple.1, tuple.2, tuple.3]
        for dim in 0 ..< 4 {
            s4DeltaSequence += 1
            let oldV = tensorVals[dim]
            let deltaBump = Float(dim == weakest ? min(Double(oldV) + inc, 1.0) : Double(oldV))
            let wire = S4DeltaWire(
                primID: primID,
                dimension: UInt8(dim),
                oldValue: oldV,
                newValue: deltaBump,
                sequence: s4DeltaSequence
            )
            guard let payload = try? S4DeltaCodec.encode(wire) else { continue }
            if !skipWire {
                await NATSBridge.shared.publishWire(subject: SubstrateWireSubjects.s4Delta, payload: payload)
            }
        }

        let rid = UUID().uuidString
        let iso = ISO8601DateFormatter().string(from: Date())
        let dimLabel = ["s1", "s2", "s3", "s4"][weakest]
        struct DomainImprovementPayload: Codable {
            let domain: String
            let dimension_improved: String
            let old_weight: Double
            let new_weight: Double
            let cycle_id: String
            let prior_health_score: Double
            let sha256: String
        }
        let payloadStruct = DomainImprovementPayload(
            domain: domain,
            dimension_improved: dimLabel,
            old_weight: oldVal,
            new_weight: newVal,
            cycle_id: cycleRowID,
            prior_health_score: priorHealthScore,
            sha256: shaContract
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let payloadJSON = (try? enc.encode(payloadStruct)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let canonReceipt = shaContract

        try? await FranklinSubstrate.shared.insertLearningReceiptWithPayload(
            id: rid,
            sessionID: sessionID,
            terminal: "CALORIE",
            receiptPath: "substrate://language_game_contracts/\(contract.id)",
            receiptSha256: canonReceipt,
            timestampISO: iso,
            kind: "domain_improvement",
            payloadJSON: payloadJSON,
            canonicalSha256: canonReceipt
        )

        return rid
    }

    private func fmt(_ x: Double) -> String {
        String(format: "%.4f", x)
    }
}
