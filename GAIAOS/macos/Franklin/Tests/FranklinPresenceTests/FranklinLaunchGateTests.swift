// ─────────────────────────────────────────────────────────────────────────────
// FranklinLaunchGateTests.swift
//
// XCTest contract for the asset gate. The same refusal codes that
// scripts/check_franklin_avatar_assets.zsh emits at build time, and that
// FranklinLaunchGate.swift emits at runtime, must fire here in CI before
// either layer ships.
//
// Each test builds a temporary fixture workspace with a synthetic
// required_assets.json and per-test asset perturbations (missing / undersized
// / hash-mismatched / valid). Coverage:
//
//   1. all 6 assets present + sized + (when pinned) hash-matched → ready=true
//   2. each individual asset removed → exactly that GW_REFUSE_ASSET_MISSING
//   3. an asset present but undersized → GW_REFUSE_ASSET_TOO_SMALL
//   4. an asset with sha256 pinned and content drifted → GW_REFUSE_ASSET_HASH_MISMATCH
//   5. voice profile missing → GW_REFUSE_FRANKLIN_VOICE_PROFILE_MISSING
//   6. voice profile present with wrong personaID → GW_REFUSE_FRANKLIN_VOICE_PROFILE_INVALID_PERSONA
//   7. required_assets.json missing → GW_REFUSE_AVATAR_REQUIRED_ASSETS_JSON_MISSING
// ─────────────────────────────────────────────────────────────────────────────

import XCTest
@testable import FranklinApp

final class FranklinLaunchGateTests: XCTestCase {

    // MARK: - Fixture helpers

    private struct FixtureAsset {
        let label: String
        let relativePath: String
        let minBytes: UInt64
        let sha256: String?
    }

    private static let canonicalAssets: [FixtureAsset] = [
        .init(label: "Franklin_Passy_V2.fblob",
              relativePath: "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.fblob",
              minBytes: 64, sha256: nil),
        .init(label: "Franklin_Z3_Materials.metallib",
              relativePath: "cells/franklin/avatar/bundle_assets/materials/Franklin_Z3_Materials.metallib",
              minBytes: 64, sha256: nil),
        .init(label: "beaver_cap_spectral_lut.exr",
              relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/beaver_cap_spectral_lut.exr",
              minBytes: 64, sha256: nil),
        .init(label: "anisotropic_flow_map.exr",
              relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/anisotropic_flow_map.exr",
              minBytes: 64, sha256: nil),
        .init(label: "claret_silk_degradation.exr",
              relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/claret_silk_degradation.exr",
              minBytes: 64, sha256: nil),
        .init(label: "styletts2_franklin_v1.coreml.mlmodelc/Manifest.json",
              relativePath: "cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc/Manifest.json",
              minBytes: 32, sha256: nil),
    ]

    private static let voiceProfileRelativePath =
        "cells/franklin/avatar/bundle_assets/voice/franklin_voice_profile.json"
    private static let validPersonaID = "franklin.guide.v1"

    /// Builds a fixture workspace under a temp dir. Returns (workspaceRoot, manifestURL).
    private func makeFixture(
        omit: Set<String> = [],
        undersize: Set<String> = [],
        hashPin: [String: String] = [:],
        skipManifest: Bool = false,
        voiceProfileMode: VoiceProfileMode = .valid
    ) throws -> (URL, URL) {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("franklin-launch-gate-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }

        // Write the assets.
        var manifestEntries: [[String: Any]] = []
        for asset in Self.canonicalAssets {
            let dst = tmp.appendingPathComponent(asset.relativePath)
            try fm.createDirectory(at: dst.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if !omit.contains(asset.label) {
                let payload: Data
                if undersize.contains(asset.label) {
                    payload = Data(repeating: 0xAB, count: 4)
                } else {
                    payload = Data(repeating: 0xAB, count: 256)
                }
                try payload.write(to: dst)
            }
            var entry: [String: Any] = [
                "label": asset.label,
                "relative_path": asset.relativePath,
                "min_bytes": asset.minBytes,
            ]
            if let pin = hashPin[asset.label] {
                entry["sha256"] = pin
            }
            manifestEntries.append(entry)
        }

        // Voice profile
        let vpPath = tmp.appendingPathComponent(Self.voiceProfileRelativePath)
        try fm.createDirectory(at: vpPath.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        switch voiceProfileMode {
        case .valid:
            let vp: [String: Any] = ["personaID": Self.validPersonaID]
            try JSONSerialization.data(withJSONObject: vp).write(to: vpPath)
        case .wrongPersona:
            let vp: [String: Any] = ["personaID": "franklin.modern.v9"]
            try JSONSerialization.data(withJSONObject: vp).write(to: vpPath)
        case .missing:
            break
        }

        // Manifest
        let manifestURL = tmp.appendingPathComponent("cells/franklin/avatar/required_assets.json")
        if !skipManifest {
            let manifestObject: [String: Any] = [
                "schema": "GFTCL-AVATAR-REQUIRED-ASSETS-001",
                "voice_profile": [
                    "relative_path": Self.voiceProfileRelativePath,
                    "required_persona_id": Self.validPersonaID,
                ],
                "required_assets": manifestEntries,
            ]
            let data = try JSONSerialization.data(withJSONObject: manifestObject,
                                                  options: [.sortedKeys, .prettyPrinted])
            try data.write(to: manifestURL)
        }
        return (tmp, manifestURL)
    }

    private enum VoiceProfileMode { case valid, wrongPersona, missing }

    // MARK: - Tests

    func test_allAssetsPresent_isReady() throws {
        let (root, manifest) = try makeFixture()
        let result = FranklinLaunchGate.evaluate(workspaceRoot: root, manifestURL: manifest)
        XCTAssertTrue(result.ready, "expected ready, got refusals=\(result.refusals)")
        XCTAssertTrue(result.refusals.isEmpty)
    }

    func test_eachMissingAsset_emitsExactRefusal() throws {
        for asset in Self.canonicalAssets {
            let (root, manifest) = try makeFixture(omit: [asset.label])
            let result = FranklinLaunchGate.evaluate(workspaceRoot: root, manifestURL: manifest)
            XCTAssertFalse(result.ready, "\(asset.label) missing must refuse")
            XCTAssertTrue(
                result.refusals.contains("GW_REFUSE_ASSET_MISSING:\(asset.label)"),
                "expected GW_REFUSE_ASSET_MISSING:\(asset.label), got \(result.refusals)"
            )
        }
    }

    func test_undersizedAsset_emitsTooSmall() throws {
        let asset = Self.canonicalAssets[0]
        let (root, manifest) = try makeFixture(undersize: [asset.label])
        let result = FranklinLaunchGate.evaluate(workspaceRoot: root, manifestURL: manifest)
        XCTAssertFalse(result.ready)
        XCTAssertTrue(
            result.refusals.contains("GW_REFUSE_ASSET_TOO_SMALL:\(asset.label)"),
            "expected too-small refusal for \(asset.label), got \(result.refusals)"
        )
    }

    func test_hashMismatch_emitsHashMismatch() throws {
        let asset = Self.canonicalAssets[0]
        // Pin a hash that cannot match the random fixture content.
        let pin = String(repeating: "0", count: 64)
        let (root, manifest) = try makeFixture(hashPin: [asset.label: pin])
        let result = FranklinLaunchGate.evaluate(workspaceRoot: root, manifestURL: manifest)
        XCTAssertFalse(result.ready)
        XCTAssertTrue(
            result.refusals.contains("GW_REFUSE_ASSET_HASH_MISMATCH:\(asset.label)"),
            "expected hash-mismatch refusal, got \(result.refusals)"
        )
    }

    func test_voiceProfileMissing_emitsRefusal() throws {
        let (root, manifest) = try makeFixture(voiceProfileMode: .missing)
        let result = FranklinLaunchGate.evaluate(workspaceRoot: root, manifestURL: manifest)
        XCTAssertFalse(result.ready)
        XCTAssertTrue(
            result.refusals.contains("GW_REFUSE_FRANKLIN_VOICE_PROFILE_MISSING"),
            "got \(result.refusals)"
        )
    }

    func test_voiceProfileWrongPersona_emitsRefusal() throws {
        let (root, manifest) = try makeFixture(voiceProfileMode: .wrongPersona)
        let result = FranklinLaunchGate.evaluate(workspaceRoot: root, manifestURL: manifest)
        XCTAssertFalse(result.ready)
        XCTAssertTrue(
            result.refusals.contains("GW_REFUSE_FRANKLIN_VOICE_PROFILE_INVALID_PERSONA"),
            "got \(result.refusals)"
        )
    }

    func test_manifestMissing_emitsRefusal() throws {
        let (root, manifest) = try makeFixture(skipManifest: true)
        let result = FranklinLaunchGate.evaluate(workspaceRoot: root, manifestURL: manifest)
        XCTAssertFalse(result.ready)
        XCTAssertTrue(
            result.refusals.contains("GW_REFUSE_AVATAR_REQUIRED_ASSETS_JSON_MISSING"),
            "got \(result.refusals)"
        )
    }

    func test_canonicalManifestEnumeratesSixAssets() throws {
        // Locking the contract: the live required_assets.json must list exactly
        // these six labels, in any order. If you add or remove an asset, this
        // test must be updated in the same commit as the JSON.
        let canonical = Self.canonicalAssets.map(\.label).sorted()
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cells/franklin/avatar/required_assets.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Live required_assets.json not on path; skipping (fixture-only run).")
        }
        let data = try Data(contentsOf: url)
        struct Manifest: Decodable {
            struct Entry: Decodable { let label: String }
            let required_assets: [Entry]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let labels = manifest.required_assets.map(\.label).sorted()
        XCTAssertEqual(labels, canonical,
                       "required_assets.json drifted from the test contract; update the test and the JSON together")
    }
}
