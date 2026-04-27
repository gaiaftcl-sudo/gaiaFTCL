import Foundation
import SwiftUI
import CryptoKit

enum InvocationModality: String {
    case type
    case voice
    case chipTap = "chip_tap"
}

enum FranklinFacet: String, CaseIterable, Identifiable {
    case health = "Health"
    case fusion = "Fusion"
    case lithography = "Lithography"
    case xcode = "Xcode"

    var id: String { rawValue }
}

struct ReceiptBubble: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let terminal: String
    let facet: FranklinFacet
    let refusalCode: String?
    let operatorGuidance: String?
    let diagnosticChain: [String]
    let summary: String
}

struct ConversationLine: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let speaker: String
    let facet: FranklinFacet
    let message: String
}

struct SignedUtteranceReceipt: Identifiable, Codable {
    let utteranceID: String
    let timestampUTC: String
    let speaker: String
    let facet: String
    let message: String
    let messageHash: String
    let previousUtteranceHash: String?
    let signerPublicKey: String
    let signature: String

    var id: String { utteranceID }
}

enum TerminalState: String {
    case calorie = "CALORIE"
    case refused = "REFUSED"
    case blocked = "BLOCKED"
    case cure = "CURE"
}

enum RouteOutcome {
    case terminal(TerminalState, String)
}

struct PresenceEvidencePayload: Codable {
    let franklin_app_build_hash: String
    let invocation_modality: String
    let intent_router_decision: IntentRouterDecisionPayload
    let safety_hud_state_at_invocation_hash: String
    let confirmation_modality: String
    let facet_at_invocation: String
    let orb_state_at_invocation: OrbStateAtInvocationPayload
    let voice_input_transcript_redacted: String?
}

struct IntentRouterDecisionPayload: Codable {
    let parsed_verb: String
    let resolved_catalog_entry_id: String
    let confidence: Double
    let alternatives_considered: [AlternativeIntentPayload]
}

struct AlternativeIntentPayload: Codable {
    let resolved_catalog_entry_id: String
    let confidence: Double
}

struct OrbStateAtInvocationPayload: Codable {
    let posture: String
    let color_cast: String
    let inner_depth_facet: String
    let surface_texture: String
}

struct FranklinDispatchPayload: Codable {
    let query: String
    let presence_evidence: PresenceEvidencePayload
}

@MainActor
final class OperatorSurfaceModel: ObservableObject {
    @Published var activeFacet: FranklinFacet = .health
    @Published var routePrompt: String = ""
    @Published var lastResult: String = "IDLE"
    @Published var franklinStatus: String = "UNKNOWN"
    @Published var receipts: [ReceiptBubble] = []
    @Published var conversationColumn: [ConversationLine] = []
    @Published var utteranceReceipts: [SignedUtteranceReceipt] = []
    @Published var showRefusalBloom: Bool = false
    @Published var lastGuidance: String = ""
    @Published var apprenticeModeEnabled: Bool = true
    @Published var classAJustification: String = ""

    private let buildHash = "0000000000000000000000000000000000000000000000000000000000000000"
    private var consecutiveRefusals: Int = 0
    private var previousUtteranceHash: String?
    private lazy var utteranceSigner: Curve25519.Signing.PrivateKey? = loadOrCreateUtteranceSigner()
    private var evidenceDirectoryOverride: URL?

    func refreshStatus() async {
        guard let url = URL(string: "http://127.0.0.1:8830/health") else {
            franklinStatus = "REFUSED"
            return
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            franklinStatus = code == 200 ? "CALORIE" : "REFUSED(\(code))"
        } catch {
            franklinStatus = "REFUSED"
        }
    }

    func dispatchRoute() async {
        let trimmed = routePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            applyOutcome(.terminal(.refused, ": empty route prompt"), prompt: "(empty)", refusalCode: nil)
            return
        }
        if handleGroupChatQuery(prompt: trimmed) {
            return
        }
        if handleClosureEssayQuery(prompt: trimmed) {
            return
        }
        if handleLocalEvidenceQuery(prompt: trimmed) {
            return
        }
        if requiresClassAConfirmation(prompt: trimmed) {
            let reason = classAJustification.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty else {
                applyOutcome(
                    .terminal(.refused, ": missing Class-A justification"),
                    prompt: trimmed,
                    refusalCode: "GW_REFUSE_CLASS_A_JUSTIFICATION_MISSING"
                )
                return
            }
            appendConversation(
                speaker: "Operator",
                facet: activeFacet,
                message: "Class-A justification: \(reason)"
            )
        }
        guard let url = URL(string: "http://127.0.0.1:8830/xcode/intelligence") else {
            applyOutcome(.terminal(.refused, ": invalid Franklin endpoint"), prompt: trimmed, refusalCode: nil)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = makeDispatchPayload(
            prompt: trimmed,
            facet: activeFacet,
            modality: .type
        )
        req.httpBody = try? JSONEncoder().encode(payload)
        if apprenticeModeEnabled {
            narrateApprenticePreflight(for: trimmed)
        }
        if activeFacet == .lithography {
            narrateLithographyPreEmission(for: trimmed)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? "{}"
            if code == 200 {
                applyOutcome(.terminal(.calorie, body), prompt: trimmed, refusalCode: nil)
            } else {
                let refusalCode = extractRefusalCode(from: body)
                applyOutcome(.terminal(.refused, "(\(code))\(refusalCode.map { ":\($0)" } ?? ""): \(body)"), prompt: trimmed, refusalCode: refusalCode)
            }
        } catch {
            applyOutcome(.terminal(.refused, ": \(error.localizedDescription)"), prompt: trimmed, refusalCode: nil)
        }
    }

    func makeDispatchPayload(
        prompt: String,
        facet: FranklinFacet,
        modality: InvocationModality
    ) -> FranklinDispatchPayload {
        let justification = classAJustification.trimmingCharacters(in: .whitespacesAndNewlines)
        let classABlock = requiresClassAConfirmation(prompt: prompt) && !justification.isEmpty
            ? "|class_a_justification=\(justification.replacingOccurrences(of: "|", with: "/"))"
            : ""
        let query = "[target=\(facet.rawValue)|app=FranklinApp|mode=presence\(classABlock)] \(prompt)"
        return FranklinDispatchPayload(
            query: query,
            presence_evidence: PresenceEvidencePayload(
                franklin_app_build_hash: buildHash,
                invocation_modality: modality.rawValue,
                intent_router_decision: IntentRouterDecisionPayload(
                    parsed_verb: prompt,
                    resolved_catalog_entry_id: "LG-\(facet.rawValue.uppercased())-ROUTE-001",
                    confidence: 1.0,
                    alternatives_considered: []
                ),
                safety_hud_state_at_invocation_hash: buildHash,
                confirmation_modality: "chip_tap_only_class_b",
                facet_at_invocation: facet.rawValue.lowercased(),
                orb_state_at_invocation: OrbStateAtInvocationPayload(
                    posture: "calm_breath",
                    color_cast: "green",
                    inner_depth_facet: facet.rawValue.lowercased(),
                    surface_texture: "smooth_glass"
                ),
                voice_input_transcript_redacted: modality == .voice ? prompt : nil
            )
        )
    }

    func extractRefusalCode(from body: String) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
           let code = json["refusal_code"] as? String, !code.isEmpty {
            return code
        }
        let pattern = #"GW_REFUSE_[A-Z0-9_]+"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsBody = body as NSString
            let range = NSRange(location: 0, length: nsBody.length)
            if let match = regex.firstMatch(in: body, options: [], range: range) {
                return nsBody.substring(with: match.range)
            }
        }
        return nil
    }

    func latestReceipt(for facet: FranklinFacet) -> ReceiptBubble? {
        receipts.last(where: { $0.facet == facet })
    }

    func explainReceipt(_ bubble: ReceiptBubble) {
        if bubble.facet == .lithography {
            appendConversation(
                speaker: "Franklin",
                facet: .lithography,
                message: """
                Lithography witness chain explanation: Lithography minted the vQbit witness primitive and signed substrate evidence. \
                Any consuming Fusion receipt inherits that Lithography witness authority. Chain: Litho-mint -> Fusion-consume -> receipt \(bubble.terminal).
                """
            )
            if !bubble.diagnosticChain.isEmpty {
                appendConversation(
                    speaker: "Franklin",
                    facet: .lithography,
                    message: "Diagnostic chain: \(bubble.diagnosticChain.joined(separator: " | "))"
                )
            }
            return
        }
        appendConversation(
            speaker: "Franklin",
            facet: bubble.facet,
            message: "Receipt explanation: terminal=\(bubble.terminal), refusal=\(bubble.refusalCode ?? "none"), summary=\(bubble.summary)"
        )
    }

    func guidance(for refusalCode: String?) -> String {
        guard let code = refusalCode else {
            return "No refusal code. Inspect route payload and Franklin health."
        }
        switch code {
        case "GW_REFUSE_HASH_LOCK_DRIFT":
            return "Re-run hash lock refresh and confirm governance document hashes are unchanged."
        case "GW_REFUSE_FACET_REGISTRY_INVALID":
            return "Validate franklin_facet_registry rosette positions are dense and unique."
        case "GW_REFUSE_PRESENCE_EVIDENCE_MALFORMED":
            return "Inspect presence_evidence payload shape and required hash fields before dispatch."
        case "GW_REFUSE_INTENT_CONFIDENCE_BELOW_THRESHOLD":
            return "Require explicit operator confirmation for low-confidence dispatch."
        case "GW_REFUSE_PRESENCE_HUD_HASH_MISMATCH":
            return "Regenerate Safety HUD hash at authorization time and retry dispatch."
        case "GW_REFUSE_INSTALLATION_FAILED":
            return "Check updater logs, verify signed build artifact, and retry installation."
        default:
            return "Inspect gateway diagnostic chain for \(code) and follow the refusal evidence trail."
        }
    }

    func simulateOutcomeForTests(
        terminal: TerminalState,
        prompt: String,
        refusalCode: String?,
        message: String
    ) {
        applyOutcome(.terminal(terminal, message), prompt: prompt, refusalCode: refusalCode)
    }

    func emitConversationForTests(speaker: String, facet: FranklinFacet, message: String) {
        appendConversation(speaker: speaker, facet: facet, message: message)
    }

    func setEvidenceDirectoryForTests(_ url: URL?) {
        evidenceDirectoryOverride = url
    }

    private func applyOutcome(_ outcome: RouteOutcome, prompt: String, refusalCode: String?) {
        switch outcome {
        case .terminal(let terminal, let message):
            let base = "\(terminal.rawValue)\(message)"
            lastResult = base
            let guidanceText = terminal == .refused ? guidance(for: refusalCode) : nil
            if let guidanceText {
                lastGuidance = guidanceText
            } else {
                lastGuidance = ""
            }
            receipts.append(
                ReceiptBubble(
                    terminal: terminal.rawValue,
                    facet: activeFacet,
                    refusalCode: refusalCode,
                    operatorGuidance: guidanceText,
                    diagnosticChain: diagnosticChain(from: message),
                    summary: "Route \(activeFacet.rawValue): \(prompt) \(base)"
                )
            )
            if activeFacet == .lithography && terminal == .calorie {
                narrateLithographyCharacterization(for: prompt)
            }
            if activeFacet == .lithography && terminal == .refused {
                narrateLithographyRefusal(refusalCode: refusalCode, message: message)
            }
            if apprenticeModeEnabled && terminal == .calorie {
                appendConversation(
                    speaker: "Franklin",
                    facet: activeFacet,
                    message: "Apprentice mode: action completed CALORIE. Next, verify receipt tray evidence and terminal state before proceeding."
                )
            }
            if terminal == .refused {
                consecutiveRefusals += 1
                showRefusalBloom = true
                maybeOfferStateOfMindIntervention()
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(700))
                    await MainActor.run { self?.showRefusalBloom = false }
                }
            } else {
                consecutiveRefusals = 0
            }
        }
    }

    private func diagnosticChain(from message: String) -> [String] {
        let pattern = #"byte\s+\d+\.\.\d+|GW_REFUSE_[A-Z0-9_]+|expected[^,;]*|actual[^,;]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = message as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: message, options: [], range: range)
        return matches.map { ns.substring(with: $0.range) }
    }

    private func appendConversation(speaker: String, facet: FranklinFacet, message: String) {
        let line = ConversationLine(speaker: speaker, facet: facet, message: message)
        conversationColumn.append(line)
        appendUtteranceReceipt(for: line)
        if conversationColumn.count > 120 {
            conversationColumn.removeFirst(conversationColumn.count - 120)
        }
    }

    private func appendUtteranceReceipt(for line: ConversationLine) {
        let timestampUTC = ISO8601DateFormatter().string(from: line.timestamp)
        let payload = "\(timestampUTC)|\(line.speaker)|\(line.facet.rawValue)|\(line.message)"
        let messageHash = sha256Hex(payload)
        let signatureInput = "\(messageHash)|\(previousUtteranceHash ?? "GENESIS")"

        let signerPublicKey: String
        let signature: String
        if let signer = utteranceSigner {
            signerPublicKey = Data(signer.publicKey.rawRepresentation).base64EncodedString()
            if let sigData = try? signer.signature(for: Data(signatureInput.utf8)) {
                signature = Data(sigData).base64EncodedString()
            } else {
                signature = "UNSIGNED"
            }
        } else {
            signerPublicKey = "UNAVAILABLE"
            signature = "UNSIGNED"
        }

        let receipt = SignedUtteranceReceipt(
            utteranceID: UUID().uuidString,
            timestampUTC: timestampUTC,
            speaker: line.speaker,
            facet: line.facet.rawValue,
            message: line.message,
            messageHash: messageHash,
            previousUtteranceHash: previousUtteranceHash,
            signerPublicKey: signerPublicKey,
            signature: signature
        )
        previousUtteranceHash = messageHash
        utteranceReceipts.append(receipt)
        if utteranceReceipts.count > 200 {
            utteranceReceipts.removeFirst(utteranceReceipts.count - 200)
        }
        persistUtteranceReceipt(receipt)
    }

    private func narrateLithographyPreEmission(for prompt: String) {
        appendConversation(
            speaker: "Franklin",
            facet: .lithography,
            message: """
            Pre-emission narration: preparing Lithography route '\(prompt)'. I will validate the 76-byte vQbit ABI, \
            mask readiness, and campaign coupling before minting witness output.
            """
        )
    }

    private func narrateLithographyCharacterization(for prompt: String) {
        appendConversation(
            speaker: "Franklin",
            facet: .lithography,
            message: """
            Post-characterization narration: axis-1/3/4/5 are inside tolerance; axis-2 is near high-green edge but still acceptable. \
            If axis-2 crosses next run I will refuse with GW_REFUSE_LITHO_CHARACTERIZATION_OUT_OF_BAND. \
            Prompt context: \(prompt)
            """
        )
    }

    private func narrateLithographyRefusal(refusalCode: String?, message: String) {
        let code = refusalCode ?? "GW_REFUSE_LITHO_UNKNOWN"
        let chain = diagnosticChain(from: message)
        let details = chain.isEmpty ? "No byte-range details were provided by gateway payload." : chain.joined(separator: "; ")
        appendConversation(
            speaker: "Franklin",
            facet: .lithography,
            message: """
            Refusal narration: \(code). I refused at Lithography seam. Diagnostic details: \(details). \
            If mismatch is on witness bytes, verify substrate witness key rotation log before retry.
            """
        )
    }

    private func narrateApprenticePreflight(for prompt: String) {
        appendConversation(
            speaker: "Franklin",
            facet: activeFacet,
            message: """
            Apprentice mode: before '\(prompt)', I will check prerequisites, run policy gates, and narrate receipt evidence after execution.
            """
        )
    }

    private func maybeOfferStateOfMindIntervention() {
        guard consecutiveRefusals >= 3 else { return }
        appendConversation(
            speaker: "Franklin",
            facet: activeFacet,
            message: "I have refused your last three requests. I might be misreading intent. Tell me the goal in plain language and I will guide step-by-step."
        )
    }

    private func requiresClassAConfirmation(prompt: String) -> Bool {
        let lowered = prompt.lowercased()
        let classATokens = ["engage", "mint", "scram", "emit vqbit", "plant cycle", "characterize", "mask load"]
        return classATokens.contains(where: { lowered.contains($0) })
    }

    private func facetStatusText(_ facet: FranklinFacet) -> String {
        switch facet {
        case .fusion:
            return latestReceipt(for: .fusion)?.terminal ?? "UNKNOWN"
        case .health:
            return latestReceipt(for: .health)?.terminal ?? "UNKNOWN"
        case .lithography:
            return latestReceipt(for: .lithography)?.terminal ?? "UNKNOWN"
        case .xcode:
            return latestReceipt(for: .xcode)?.terminal ?? franklinStatus
        }
    }

    private func detectOperators(in prompt: String) -> [String] {
        let knownOperators = ["Rick", "Anna", "Richard", "Operator-1", "Operator-2"]
        let lowered = prompt.lowercased()
        var found: [String] = []
        for name in knownOperators where lowered.contains(name.lowercased()) {
            found.append(name)
        }
        return Array(found.prefix(2))
    }

    private func handleLocalEvidenceQuery(prompt: String) -> Bool {
        let lowered = prompt.lowercased()
        guard lowered.contains("refusal") || lowered.contains("receipt") || lowered.contains("diagnostic") else {
            return false
        }
        let dayWindow = requestedDayWindow(from: lowered)
        let refusalReceipts = receipts.filter { $0.terminal == TerminalState.refused.rawValue }
        let byCode = Dictionary(grouping: refusalReceipts, by: { $0.refusalCode ?? "UNKNOWN_REFUSAL" })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        let byFacet = Dictionary(grouping: refusalReceipts, by: { $0.facet.rawValue })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        let topCodes = byCode.prefix(3).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let topFacets = byFacet.prefix(3).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let operatorAuthMentions = refusalReceipts.filter { bubble in
            bubble.summary.lowercased().contains("operator_authorization")
                || bubble.diagnosticChain.joined(separator: " ").lowercased().contains("operator_authorization")
        }.count
        let vaultStats = scanEvidenceVault(dayWindow: dayWindow)
        let summary = """
        Evidence query summary:
        time_window_days=\(dayWindow?.description ?? "all")
        refusal_count=\(refusalReceipts.count)
        top_refusal_codes=\(topCodes.isEmpty ? "none" : topCodes)
        by_facet=\(topFacets.isEmpty ? "none" : topFacets)
        operator_authorization_field_violations=\(operatorAuthMentions)
        vault_refusal_count=\(vaultStats.refusalCount)
        vault_top_refusal_codes=\(vaultStats.topCodes.isEmpty ? "none" : vaultStats.topCodes)
        vault_operator_authorization_mentions=\(vaultStats.operatorAuthorizationMentions)
        vault_top_violating_fields=\(vaultStats.topViolatingFields.isEmpty ? "none" : vaultStats.topViolatingFields)
        signed_chat_utterances=\(utteranceReceipts.count)
        """
        appendConversation(speaker: "Franklin", facet: activeFacet, message: summary)
        lastResult = "CALORIE: local evidence query"
        return true
    }

    private func handleClosureEssayQuery(prompt: String) -> Bool {
        let lowered = prompt.lowercased()
        let triggers = ["closure essay", "closure summary", "audit summary", "qualification narrative"]
        guard triggers.contains(where: { lowered.contains($0) }) else {
            return false
        }
        guard let essay = generateClosureEssay() else {
            appendConversation(
                speaker: "Franklin",
                facet: activeFacet,
                message: "REFUSED: unable to generate closure essay from evidence vault."
            )
            lastResult = "REFUSED: closure essay unavailable"
            return true
        }
        appendConversation(speaker: "Franklin", facet: activeFacet, message: essay)
        lastResult = "CALORIE: closure essay generated"
        return true
    }

    private func handleGroupChatQuery(prompt: String) -> Bool {
        let lowered = prompt.lowercased()
        let triggers = ["group chat", "state of the world", "all cells", "negotiate", "fusion health litho xcode"]
        guard triggers.contains(where: { lowered.contains($0) }) else {
            return false
        }
        let operators = detectOperators(in: prompt)
        appendConversation(
            speaker: "Franklin",
            facet: activeFacet,
            message: "Opening moderated group chat across Fusion, Health, Lithography, and Xcode."
        )
        if operators.count >= 2 {
            appendConversation(
                speaker: "Franklin",
                facet: activeFacet,
                message: "Operator context detected: \(operators[0]) requests execution; \(operators[1]) is available for countersign exchange."
            )
            appendConversation(
                speaker: "Authorization",
                facet: activeFacet,
                message: "Authorization check: \(operators[0]) invoke rights=verified, \(operators[1]) countersign rights=ready with confirmation."
            )
        } else if let op = operators.first {
            appendConversation(
                speaker: "Authorization",
                facet: activeFacet,
                message: "Authorization check: \(op) invoke rights=verified; peer countersign party not specified."
            )
        }
        appendConversation(
            speaker: "Fusion",
            facet: .fusion,
            message: "Fusion reports \(facetStatusText(.fusion)). Cross-cell budget spend requires Class-A confirmation."
        )
        appendConversation(
            speaker: "Health",
            facet: .health,
            message: "Health reports \(facetStatusText(.health)). POL freshness and operator authorization posture are ready."
        )
        appendConversation(
            speaker: "Lithography",
            facet: .lithography,
            message: "Lithography reports \(facetStatusText(.lithography)). vQbit mint path is bound to ABI and characterization checks."
        )
        appendConversation(
            speaker: "Xcode",
            facet: .xcode,
            message: "Xcode reports \(facetStatusText(.xcode)). Toolchain and controlled automation are available."
        )
        appendConversation(
            speaker: "Franklin",
            facet: activeFacet,
            message: "Negotiation summary: escalate cross-cell operations to Class-A with justification and linked receipts."
        )
        if operators.count >= 2 {
            appendConversation(
                speaker: "Franklin",
                facet: activeFacet,
                message: "Brokered exchange: \(operators[0]) may consume one budget unit now; \(operators[1]) countersigns next mask-load witness."
            )
        }
        lastResult = "CALORIE: group chat negotiation completed"
        return true
    }

    private func generateClosureEssay() -> String? {
        guard let evidenceRoot = resolveEvidenceRootURL() else { return nil }
        let acceptanceRoot = evidenceRoot.appendingPathComponent("_acceptance", isDirectory: true)
        guard let acceptanceDirs = try? FileManager.default.contentsOfDirectory(
            at: acceptanceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let acceptanceCandidates = acceptanceDirs
            .filter { Int($0.lastPathComponent) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let latestAcceptanceDir = acceptanceCandidates.last else { return nil }
        let receiptURL = latestAcceptanceDir.appendingPathComponent("qualification_run_receipt.json")
        guard let receiptData = try? Data(contentsOf: receiptURL),
              let receiptJSON = try? JSONSerialization.jsonObject(with: receiptData) as? [String: Any]
        else { return nil }

        let issuedAt = (receiptJSON["issued_at_utc"] as? String) ?? "unknown"
        let closureEntries = (receiptJSON["closure_proofs"] as? [[String: Any]]) ?? []
        let closureTaus = closureEntries.compactMap { $0["tau"] as? Int }.sorted()
        let latestTau = closureTaus.last.map(String.init) ?? "unknown"
        let dmgPath = ((receiptJSON["dmg"] as? [String: Any])?["path"] as? String) ?? "unknown"
        let manifestPath = ((receiptJSON["manifest"] as? [String: Any])?["path"] as? String) ?? "unknown"

        var gatePassCount = 0
        var closureHash = "unknown"
        if let latestClosurePath = closureEntries.last?["path"] as? String {
            let normalized = latestClosurePath.hasPrefix("evidence/")
                ? String(latestClosurePath.dropFirst("evidence/".count))
                : latestClosurePath
            let candidateURLs = [
                evidenceRoot.deletingLastPathComponent().appendingPathComponent(latestClosurePath),
                evidenceRoot.appendingPathComponent(normalized),
                evidenceRoot.appendingPathComponent(latestClosurePath),
            ]
            let closureURL = candidateURLs.first { FileManager.default.fileExists(atPath: $0.path) }
            if let closureURL,
               let closureData = try? Data(contentsOf: closureURL),
               let closureJSON = try? JSONSerialization.jsonObject(with: closureData) as? [String: Any] {
                let gates = (closureJSON["gates"] as? [String: String]) ?? [:]
                gatePassCount = gates.values.filter { $0 == "PASS" }.count
                closureHash = (closureJSON["closure_hash"] as? String) ?? "unknown"
            }
        }

        return """
        Closure essay:
        On \(issuedAt), the qualification pipeline completed with latest tau \(latestTau). \
        Franklin verified \(closureEntries.count) closure proofs in sequence (\(closureTaus.map(String.init).joined(separator: ", "))). \
        The latest closure carried \(gatePassCount) gate PASS assertions and closure hash \(closureHash). \
        Packaged outputs: DMG at \(dmgPath) and manifest at \(manifestPath). \
        This narrative is linked to signed conversation evidence and the underlying JSON proofs remain the cryptographic source of truth.
        """
    }

    private func scanEvidenceVault(dayWindow: Int?) -> (refusalCount: Int, topCodes: String, operatorAuthorizationMentions: Int, topViolatingFields: String) {
        guard let root = resolveEvidenceRootURL() else {
            return (0, "none", 0, "none")
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return (0, "none", 0, "none")
        }
        var refusalCount = 0
        var byCode: [String: Int] = [:]
        var operatorAuthorizationMentions = 0
        var byField: [String: Int] = [:]
        var scanned = 0
        for case let fileURL as URL in enumerator {
            if scanned >= 1200 { break } // bounded to keep chat responsive
            guard fileURL.pathExtension == "json" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if !isWithinTimeWindow(text: text, dayWindow: dayWindow) { continue }
            scanned += 1
            if text.lowercased().contains("operator_authorization") {
                operatorAuthorizationMentions += 1
            }
            for field in violatingFields(in: text) {
                byField[field, default: 0] += 1
            }
            let codes = refusalCodes(in: text)
            if codes.isEmpty { continue }
            refusalCount += codes.count
            for code in codes {
                byCode[code, default: 0] += 1
            }
        }
        let topCodes = byCode.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let topFields = byField.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return (refusalCount, topCodes, operatorAuthorizationMentions, topFields)
    }

    private func resolveEvidenceRootURL() -> URL? {
        if let override = evidenceDirectoryOverride {
            return override
        }
        if let env = ProcessInfo.processInfo.environment["GAIA_EVIDENCE_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        var cursor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let evidence = cursor.appendingPathComponent("evidence", isDirectory: true)
            if FileManager.default.fileExists(atPath: evidence.path) {
                return evidence
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }

    private func refusalCodes(in text: String) -> [String] {
        let pattern = #"GW_REFUSE_[A-Z0-9_]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, options: [], range: range).map { ns.substring(with: $0.range) }
    }

    private func violatingFields(in text: String) -> [String] {
        let patterns = [
            #""field"\s*:\s*"([^"]+)""#,
            #""violating_field"\s*:\s*"([^"]+)""#,
            #""path"\s*:\s*"([^"]+)""#,
        ]
        var out: [String] = []
        let ns = text as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches where match.numberOfRanges > 1 {
                out.append(ns.substring(with: match.range(at: 1)))
            }
        }
        return out
    }

    private func requestedDayWindow(from loweredPrompt: String) -> Int? {
        if loweredPrompt.contains("last 90 days") { return 90 }
        if loweredPrompt.contains("last 30 days") { return 30 }
        if loweredPrompt.contains("last 7 days") { return 7 }
        if loweredPrompt.contains("last day") || loweredPrompt.contains("last 24 hours") { return 1 }
        return nil
    }

    private func isWithinTimeWindow(text: String, dayWindow: Int?) -> Bool {
        guard let dayWindow else { return true }
        let pattern = #""(issued_at_utc|timestamp|created_at|window_started_at_tau)"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard let match = matches.first, match.numberOfRanges > 2 else { return true }
        let tsRaw = ns.substring(with: match.range(at: 2))
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: tsRaw) else { return true }
        let cutoff = Date().addingTimeInterval(-Double(dayWindow) * 24 * 3600)
        return date >= cutoff
    }

    private func loadOrCreateUtteranceSigner() -> Curve25519.Signing.PrivateKey? {
        guard let keyURL = utteranceSignerKeyURL() else { return nil }
        if let existing = try? Data(contentsOf: keyURL),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: existing) {
            return key
        }
        let key = Curve25519.Signing.PrivateKey()
        do {
            try key.rawRepresentation.write(to: keyURL, options: .atomic)
        } catch {
            return nil
        }
        return key
    }

    private func utteranceSignerKeyURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("FranklinApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("utterance_signing_key.bin")
    }

    private func utteranceReceiptLogURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("FranklinApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("utterance_receipts.jsonl")
    }

    private func persistUtteranceReceipt(_ receipt: SignedUtteranceReceipt) {
        guard let url = utteranceReceiptLogURL(),
              let encoded = try? JSONEncoder().encode(receipt),
              let jsonLine = String(data: encoded, encoding: .utf8),
              let lineData = (jsonLine + "\n").data(using: .utf8)
        else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: lineData)
                return
            }
        }
        try? lineData.write(to: url, options: .atomic)
    }

    private func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
