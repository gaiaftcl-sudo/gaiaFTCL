import XCTest
import SwiftUI
import Foundation
@testable import FranklinUIKit
@testable import FranklinApp

final class FranklinPresenceTests: XCTestCase {
    func testPrimaryWindowContractIsFullFranklinUI() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp/FranklinApp.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)

        guard let primaryRange = source.range(of: #"WindowGroup\("Franklin"\) \{\s*CanvasView\(\)"#, options: .regularExpression) else {
            XCTFail("Primary Franklin window must host CanvasView.")
            return
        }
        guard let presenceRange = source.range(of: #"WindowGroup\("Franklin Avatar Presence"\) \{\s*AvatarView"#, options: .regularExpression) else {
            XCTFail("Secondary presence window must host AvatarView.")
            return
        }

        XCTAssertLessThan(primaryRange.lowerBound.utf16Offset(in: source), presenceRange.lowerBound.utf16Offset(in: source))
    }

    func testHouseSpringExists() {
        _ = Animation.franklin
    }

    @MainActor
    func testDispatchPayloadContainsPresenceEvidence() throws {
        let model = OperatorSurfaceModel()
        let payload = model.makeDispatchPayload(
            prompt: "engage cycle",
            facet: .fusion,
            modality: .type
        )
        XCTAssertTrue(payload.query.contains("target=Fusion"))
        XCTAssertTrue(payload.query.contains("guide=franklin_avatar"))
        XCTAssertEqual(payload.presence_evidence.facet_at_invocation, "fusion")
        XCTAssertEqual(payload.presence_evidence.invocation_modality, "type")
        XCTAssertEqual(payload.presence_evidence.confirmation_modality, "chip_tap_only_class_b")
    }

    @MainActor
    func testExtractRefusalCodeFromJSON() {
        let model = OperatorSurfaceModel()
        let body = #"{"refusal_code":"GW_REFUSE_PRESENCE_EVIDENCE_MALFORMED","msg":"bad"}"#
        XCTAssertEqual(
            model.extractRefusalCode(from: body),
            "GW_REFUSE_PRESENCE_EVIDENCE_MALFORMED"
        )
    }

    @MainActor
    func testLatestReceiptByFacet() {
        let model = OperatorSurfaceModel()
        model.receipts = [
            ReceiptBubble(terminal: "CALORIE", facet: .health, refusalCode: nil, operatorGuidance: nil, diagnosticChain: [], summary: "h"),
            ReceiptBubble(terminal: "REFUSED", facet: .fusion, refusalCode: "GW_REFUSE_HASH_LOCK_DRIFT", operatorGuidance: nil, diagnosticChain: [], summary: "f1"),
            ReceiptBubble(terminal: "CALORIE", facet: .fusion, refusalCode: nil, operatorGuidance: nil, diagnosticChain: [], summary: "f2"),
        ]
        let latestFusion = model.latestReceipt(for: .fusion)
        XCTAssertEqual(latestFusion?.summary, "f2")
        XCTAssertEqual(latestFusion?.terminal, "CALORIE")
    }

    @MainActor
    func testGuidanceMappingForKnownRefusalCode() {
        let model = OperatorSurfaceModel()
        let guidance = model.guidance(for: "GW_REFUSE_PRESENCE_EVIDENCE_MALFORMED")
        XCTAssertTrue(guidance.contains("presence_evidence"))
    }

    @MainActor
    func testRefusalOutcomeSetsGuidanceAndBloom() {
        let model = OperatorSurfaceModel()
        model.activeFacet = .xcode
        model.simulateOutcomeForTests(
            terminal: .refused,
            prompt: "commit",
            refusalCode: "GW_REFUSE_INSTALLATION_FAILED",
            message: "(58): updater install failed"
        )
        XCTAssertTrue(model.showRefusalBloom)
        XCTAssertTrue(model.lastResult.hasPrefix("REFUSED"))
        XCTAssertTrue(model.lastGuidance.contains("updater logs"))
        XCTAssertEqual(model.latestReceipt(for: .xcode)?.refusalCode, "GW_REFUSE_INSTALLATION_FAILED")
    }

    @MainActor
    func testCalorieOutcomeClearsGuidance() {
        let model = OperatorSurfaceModel()
        model.simulateOutcomeForTests(
            terminal: .refused,
            prompt: "probe",
            refusalCode: "GW_REFUSE_HASH_LOCK_DRIFT",
            message: "(51): drift"
        )
        XCTAssertFalse(model.lastGuidance.isEmpty)

        model.simulateOutcomeForTests(
            terminal: .calorie,
            prompt: "probe",
            refusalCode: nil,
            message: ": ok"
        )
        XCTAssertEqual(model.lastGuidance, "")
        XCTAssertTrue(model.lastResult.hasPrefix("CALORIE"))
    }

    @MainActor
    func testLithographyRefusalNarrationAddedToConversation() {
        let model = OperatorSurfaceModel()
        model.activeFacet = .lithography
        model.simulateOutcomeForTests(
            terminal: .refused,
            prompt: "validate abi",
            refusalCode: "GW_REFUSE_PRESENCE_EVIDENCE_MALFORMED",
            message: "byte 12..43 mismatch expected 0xa7c4 actual 0x9b81"
        )
        XCTAssertFalse(model.conversationColumn.isEmpty)
        let latest = model.conversationColumn.last?.message ?? ""
        XCTAssertTrue(latest.contains("Refusal narration"))
        XCTAssertTrue(latest.contains("byte 12..43"))
    }

    @MainActor
    func testExplainLithographyReceiptAddsWitnessNarration() {
        let model = OperatorSurfaceModel()
        let bubble = ReceiptBubble(
            terminal: "CALORIE",
            facet: .lithography,
            refusalCode: nil,
            operatorGuidance: nil,
            diagnosticChain: ["byte 0..3 schema ok"],
            summary: "litho summary"
        )
        model.explainReceipt(bubble)
        let latest = model.conversationColumn.last?.message ?? ""
        XCTAssertTrue(latest.contains("Diagnostic chain"))
    }

    @MainActor
    func testLithographyCalorieAddsCharacterizationNarration() {
        let model = OperatorSurfaceModel()
        model.activeFacet = .lithography
        model.simulateOutcomeForTests(
            terminal: .calorie,
            prompt: "characterize b2cn",
            refusalCode: nil,
            message: ": ok"
        )
        let joined = model.conversationColumn.map(\.message).joined(separator: "\n")
        XCTAssertTrue(joined.contains("Post-characterization narration"))
        XCTAssertTrue(joined.contains("axis-2"))
    }

    @MainActor
    func testClassAConfirmationRequiresJustification() {
        let model = OperatorSurfaceModel()
        let payloadWithout = model.makeDispatchPayload(
            prompt: "engage cycle",
            facet: .fusion,
            modality: .type
        )
        XCTAssertFalse(payloadWithout.query.contains("class_a_justification"))

        model.classAJustification = "Need cycle for audit readiness."
        let payloadWith = model.makeDispatchPayload(
            prompt: "engage cycle",
            facet: .fusion,
            modality: .type
        )
        XCTAssertTrue(payloadWith.query.contains("class_a_justification"))
    }

    @MainActor
    func testThreeRefusalsTriggerStateOfMindIntervention() {
        let model = OperatorSurfaceModel()
        model.activeFacet = .fusion
        model.simulateOutcomeForTests(
            terminal: .refused,
            prompt: "engage 1",
            refusalCode: "GW_REFUSE_HASH_LOCK_DRIFT",
            message: "first"
        )
        model.simulateOutcomeForTests(
            terminal: .refused,
            prompt: "engage 2",
            refusalCode: "GW_REFUSE_HASH_LOCK_DRIFT",
            message: "second"
        )
        model.simulateOutcomeForTests(
            terminal: .refused,
            prompt: "engage 3",
            refusalCode: "GW_REFUSE_HASH_LOCK_DRIFT",
            message: "third"
        )
        let joined = model.conversationColumn.map(\.message).joined(separator: "\n")
        XCTAssertTrue(joined.contains("last three requests"))
    }

    @MainActor
    func testApprenticeModeNarratesPreflightAndSuccess() {
        let model = OperatorSurfaceModel()
        model.activeFacet = .health
        model.simulateOutcomeForTests(
            terminal: .calorie,
            prompt: "prefight",
            refusalCode: nil,
            message: ": ok"
        )
        let joined = model.conversationColumn.map(\.message).joined(separator: "\n")
        XCTAssertTrue(joined.contains("action completed CALORIE"))
    }

    @MainActor
    func testSignedUtteranceReceiptsAreHashChained() {
        let model = OperatorSurfaceModel()
        model.emitConversationForTests(speaker: "Franklin", facet: .fusion, message: "first line")
        model.emitConversationForTests(speaker: "Franklin", facet: .fusion, message: "second line")

        XCTAssertEqual(model.utteranceReceipts.count, 2)
        let first = model.utteranceReceipts[0]
        let second = model.utteranceReceipts[1]
        XCTAssertNil(first.previousUtteranceHash)
        XCTAssertEqual(second.previousUtteranceHash, first.messageHash)
        XCTAssertFalse(first.messageHash.isEmpty)
        XCTAssertFalse(second.signature.isEmpty)
    }

    @MainActor
    func testEvidenceQuerySummarizesRefusalsInChat() async {
        let model = OperatorSurfaceModel()
        model.activeFacet = .fusion
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let evidenceFile = tempDir.appendingPathComponent("sample.json")
        let sample = #"{"issued_at_utc":"2026-04-25T15:39:50Z","refusal_code":"GW_REFUSE_HASH_LOCK_DRIFT","diagnostic":"operator_authorization mismatch","field":"fm_provenance.operator_authorization"}"#
        try? sample.write(to: evidenceFile, atomically: true, encoding: .utf8)
        model.setEvidenceDirectoryForTests(tempDir)
        model.simulateOutcomeForTests(
            terminal: .refused,
            prompt: "engage",
            refusalCode: "GW_REFUSE_HASH_LOCK_DRIFT",
            message: "operator_authorization missing"
        )
        model.routePrompt = "find me every refusal in the last 90 days where operator_authorization was the violating field"
        await model.dispatchRoute()
        let latest = model.conversationColumn.last?.message ?? ""
        XCTAssertTrue(latest.contains("Evidence query summary"))
        XCTAssertTrue(latest.contains("time_window_days=90"))
        XCTAssertTrue(latest.contains("refusal_count=1"))
        XCTAssertTrue(latest.contains("operator_authorization_field_violations=1"))
        XCTAssertTrue(latest.contains("vault_refusal_count=1"))
        XCTAssertTrue(latest.contains("vault_operator_authorization_mentions=1"))
        XCTAssertTrue(latest.contains("vault_top_violating_fields=fm_provenance.operator_authorization=1"))
    }

    @MainActor
    func testClosureEssayGeneratedFromEvidenceVault() async {
        let model = OperatorSurfaceModel()
        model.activeFacet = .fusion
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let acceptanceDir = tempDir.appendingPathComponent("_acceptance/123", isDirectory: true)
        let closureDir = tempDir.appendingPathComponent("_closure/123", isDirectory: true)
        try? FileManager.default.createDirectory(at: acceptanceDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: closureDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let closure = """
        {
          "gates": { "gate1": "PASS", "gate2": "PASS" },
          "closure_hash": "abc123"
        }
        """
        try? closure.write(
            to: closureDir.appendingPathComponent("closure_proof.json"),
            atomically: true,
            encoding: .utf8
        )
        let receipt = """
        {
          "issued_at_utc": "2026-04-26T11:00:00Z",
          "closure_proofs": [
            { "tau": 123, "path": "evidence/_closure/123/closure_proof.json" }
          ],
          "dmg": { "path": "dist/test.dmg" },
          "manifest": { "path": "dist/test.json" }
        }
        """
        try? receipt.write(
            to: acceptanceDir.appendingPathComponent("qualification_run_receipt.json"),
            atomically: true,
            encoding: .utf8
        )

        model.setEvidenceDirectoryForTests(tempDir)
        model.routePrompt = "write closure essay"
        await model.dispatchRoute()
        let latest = model.conversationColumn.last?.message ?? ""
        XCTAssertTrue(latest.contains("Closure essay:"))
        XCTAssertTrue(latest.contains("latest tau 123"))
        XCTAssertTrue(latest.contains("closure hash abc123"))
    }

    @MainActor
    func testGroupChatNegotiationAddsMultiFacetConversation() async {
        let model = OperatorSurfaceModel()
        model.routePrompt = "Fusion Health Litho Xcode state of the world group chat"
        await model.dispatchRoute()
        let joined = model.conversationColumn.map(\.message).joined(separator: "\n")
        XCTAssertTrue(joined.contains("Opening moderated group chat"))
        XCTAssertTrue(joined.contains("Fusion reports"))
        XCTAssertTrue(joined.contains("Health reports"))
        XCTAssertTrue(joined.contains("Lithography reports"))
        XCTAssertTrue(joined.contains("Xcode reports"))
        XCTAssertTrue(joined.contains("Negotiation summary"))
    }

    @MainActor
    func testGroupChatIncludesMultiOperatorAuthorizationAndExchange() async {
        let model = OperatorSurfaceModel()
        model.routePrompt = "Group chat: Rick asks to consume one vQbit and Anna will countersign next mask load."
        await model.dispatchRoute()
        let joined = model.conversationColumn.map(\.message).joined(separator: "\n")
        XCTAssertTrue(joined.contains("Operator context detected: Rick requests execution; Anna is available for countersign exchange."))
        XCTAssertTrue(joined.contains("Authorization check: Rick invoke rights=verified, Anna countersign rights=ready with confirmation."))
        XCTAssertTrue(joined.contains("Brokered exchange: Rick may consume one budget unit now; Anna countersigns next mask-load witness."))
    }

    @MainActor
    func testAvatarGuideExposesFacetAndSharedLanguageGames() {
        let model = OperatorSurfaceModel()
        model.activeFacet = .fusion
        let games = model.currentFacetLanguageGames().map(\.id)
        XCTAssertTrue(games.contains("LG-FUSION-ROUTE-001"))
        XCTAssertTrue(games.contains("LG-FRANKLIN-OQ-AVATAR-TESTS-001"))
        XCTAssertTrue(games.contains("LG-FRANKLIN-PQ-AVATAR-LIFELIKE-001"))
    }

    @MainActor
    func testAvatarGreetGuideWritesConversationGuidance() {
        let model = OperatorSurfaceModel()
        model.activeFacet = .xcode
        model.avatarGreetAndGuide()
        let joined = model.conversationColumn.map(\.message).joined(separator: "\n")
        XCTAssertTrue(joined.contains("Welcome. I am your avatar control surface"))
        XCTAssertTrue(joined.contains("Available language games for Xcode"))
    }

    @MainActor
    func testRecordingToggleWritesReceiptPath() throws {
        let model = OperatorSurfaceModel()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        model.setEvidenceDirectoryForTests(tempDir)

        model.toggleRecording()
        XCTAssertTrue(model.avatarRecordingEnabled)

        model.toggleRecording()
        XCTAssertFalse(model.avatarRecordingEnabled)
        XCTAssertFalse(model.latestRecordingReceiptPath.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.latestRecordingReceiptPath))
    }

    func testAvatarStageUsesRuntimeRendererContract() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp/CanvasView.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)
        XCTAssertTrue(source.contains("FranklinAvatarRuntimeView"))
        XCTAssertTrue(source.contains("Greet + Guide"))
    }

    func testAvatarRuntimeUsesMetalHostAndNoSceneKitPrimitives() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp/FranklinAvatarRuntime.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)
        XCTAssertTrue(source.contains("import Metal"))
        XCTAssertTrue(source.contains("import MetalKit"))
        XCTAssertTrue(source.contains("MTKView"))
        XCTAssertFalse(source.contains("import SceneKit"))
        XCTAssertFalse(source.contains("SCNSphere"))
        XCTAssertFalse(source.contains("SCNTorus"))
        XCTAssertFalse(source.contains("SCNCapsule"))
    }

    func testAvatarRuntimeBindsBridgeAndRigChannels() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp/FranklinAvatarRuntime.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)
        XCTAssertTrue(source.contains("FranklinRustBridge.shared.version"))
        XCTAssertTrue(source.contains("FranklinRustBridge.shared.firstViseme"))
        XCTAssertTrue(source.contains("GW_REFUSE_AVATAR_FRAME_BUDGET_OVERRUN"))
        XCTAssertTrue(source.contains("pose_templates/viseme"))
        XCTAssertTrue(source.contains("pose_templates/expression"))
        XCTAssertTrue(source.contains("pose_templates/posture"))
        XCTAssertTrue(source.contains("GW_REFUSE_AVATAR_MESH_ASSET_MISSING"))
        XCTAssertTrue(source.contains("GW_REFUSE_AVATAR_RIG_VISEME_CARDINALITY"))
        XCTAssertTrue(source.contains("GW_REFUSE_AVATAR_RIG_EXPRESSION_CARDINALITY"))
        XCTAssertTrue(source.contains("GW_REFUSE_AVATAR_RIG_POSTURE_CARDINALITY"))
    }

    func testSproutVisibleReceiptCarriesLifelikeInvariantFields() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp/SproutEvidenceCoordinator.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)
        XCTAssertTrue(source.contains("\"avatar_mode\": \"lifelike_3d_runtime\""))
        XCTAssertTrue(source.contains("\"avatar_controls\""))
        XCTAssertTrue(source.contains("\"language_game_launcher\""))
        XCTAssertTrue(source.contains("\"material_system\""))
        XCTAssertTrue(source.contains("\"period_profile\": \"passy_1778\""))
        XCTAssertTrue(source.contains("\"lithography_contract\""))
        XCTAssertTrue(source.contains("LG-LITHO-EXPOSE-001"))
    }

    @MainActor
    func testLithographyCatalogIncludesMaterialScienceGames() {
        let games = FranklinLanguageGameCatalog.byFacet[.lithography] ?? []
        let ids = games.map(\.id)
        XCTAssertTrue(ids.contains("LG-LITHOGRAPHY-ROUTE-001"))
        XCTAssertTrue(ids.contains("LG-LITHO-EXPOSE-001"))
        XCTAssertTrue(ids.contains("LG-FRANKLIN-OQ-LITHO-TESTS-001"))
        XCTAssertTrue(games.contains(where: { $0.title.lowercased().contains("characterization") }))
    }

    func testRustBridgeLoadsDeterministicSymbols() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp/FranklinRustBridge.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)
        XCTAssertTrue(source.contains("franklin_avatar_bridge_version"))
        XCTAssertTrue(source.contains("franklin_avatar_validate_frame"))
        XCTAssertTrue(source.contains("franklin_avatar_first_viseme"))
        XCTAssertTrue(source.contains("libavatar_bridge.dylib"))
    }

    func testLiveIOServicesUseAppleLocalFrameworks() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp/FranklinLiveIOServices.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)
        XCTAssertTrue(source.contains("import Speech"))
        XCTAssertTrue(source.contains("import Vision"))
        XCTAssertTrue(source.contains("SFSpeechRecognizer"))
        XCTAssertTrue(source.contains("VNDetectFaceLandmarksRequest"))
        XCTAssertTrue(source.contains("LanguageModelSession"))
        XCTAssertTrue(source.contains("franklin_voice_profile.json"))
        XCTAssertTrue(source.contains("AVSpeechSynthesisVoice(identifier: voiceProfile.preferredVoiceIdentifier)"))
    }

    func testAvatarSourceContainsNoSimulationLanguage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp")
        let files = [
            "FranklinAvatarRuntime.swift",
            "FranklinLiveIOServices.swift",
            "FranklinRustBridge.swift",
        ]
        for file in files {
            let content = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8).lowercased()
            XCTAssertFalse(content.contains("simulate"))
            XCTAssertFalse(content.contains("mock"))
        }
    }

    func testCanvasShowsExplicitMissingMeshRefusal() throws {
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FranklinApp/CanvasView.swift")
        let source = try String(contentsOf: sourcePath, encoding: .utf8)
        XCTAssertTrue(source.contains("REFUSED: missing Passy mesh asset"))
    }

    func testVisibleContractBuilderResolvesBundleAndCountsMaterialRigAssets() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let avatarRoot = root.appendingPathComponent("cells/franklin/avatar", isDirectory: true)
        let bundleDir = avatarRoot.appendingPathComponent("build/avatar_bundle", isDirectory: true)
        let illuminants = avatarRoot.appendingPathComponent("bundle_assets/illuminants", isDirectory: true)
        let visemes = avatarRoot.appendingPathComponent("bundle_assets/pose_templates/viseme", isDirectory: true)
        let expressions = avatarRoot.appendingPathComponent("bundle_assets/pose_templates/expression", isDirectory: true)
        let postures = avatarRoot.appendingPathComponent("bundle_assets/pose_templates/posture", isDirectory: true)
        let evidence = avatarRoot.appendingPathComponent("evidence", isDirectory: true)
        try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: illuminants, withIntermediateDirectories: true)
        try fm.createDirectory(at: visemes, withIntermediateDirectories: true)
        try fm.createDirectory(at: expressions, withIntermediateDirectories: true)
        try fm.createDirectory(at: postures, withIntermediateDirectories: true)
        try fm.createDirectory(at: evidence, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        for i in 0..<4 { fm.createFile(atPath: illuminants.appendingPathComponent("i\(i).json").path, contents: Data()) }
        for i in 0..<11 { fm.createFile(atPath: visemes.appendingPathComponent("v\(i).json").path, contents: Data()) }
        for i in 0..<12 { fm.createFile(atPath: expressions.appendingPathComponent("e\(i).json").path, contents: Data()) }
        for i in 0..<6 { fm.createFile(atPath: postures.appendingPathComponent("p\(i).json").path, contents: Data()) }

        let body = SproutVisibleContractBuilder.build(
            evidenceRoot: evidence,
            avatarBundlePath: bundleDir.path,
            tau: "TEST-TAU",
            now: Date(timeIntervalSince1970: 0)
        )
        let material = body["material_system"] as? [String: Any]
        let rig = body["rig_channels"] as? [String: Int]
        let litho = body["lithography_contract"] as? [String: Any]
        let required = litho?["required_games"] as? [String]

        XCTAssertEqual(material?["illuminants"] as? Int, 4)
        XCTAssertEqual(material?["period_profile"] as? String, "passy_1778")
        XCTAssertEqual(rig?["visemes"], 11)
        XCTAssertEqual(rig?["expressions"], 12)
        XCTAssertEqual(rig?["postures"], 6)
        XCTAssertTrue(required?.contains("LG-LITHO-EXPOSE-001") == true)
    }
}
