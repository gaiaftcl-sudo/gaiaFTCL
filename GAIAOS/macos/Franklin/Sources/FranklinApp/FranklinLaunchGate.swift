// ─────────────────────────────────────────────────────────────────────────────
// FranklinLaunchGate.swift
//
// Runtime asset gate. Reads cells/franklin/avatar/required_assets.json (the
// same file the SwiftPM build-tool plugin consumes) and refuses launch if any
// required Passy asset is missing, undersized, or hash-mismatched, or if the
// voice-profile contract is violated.
//
// Contract is shared with:
//   • scripts/check_franklin_avatar_assets.zsh (build-time gate)
//   • Plugins/CheckFranklinAvatarAssets/      (SwiftPM plugin)
//   • Tests/FranklinPresenceTests/            (XCTest contract)
//
// All three layers MUST emit the same refusal codes for the same conditions.
// If you edit this file, update required_assets.json and the test fixtures.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

struct FranklinLaunchGateResult {
    let ready: Bool
    let refusals: [String]
}

enum FranklinLaunchGate {

    // MARK: - JSON contract

    private struct RequiredAssetsManifest: Decodable {
        let voiceProfile: VoiceProfileEntry?
        let requiredAssets: [RequiredAssetEntry]
        let forbiddenSubstrings: [String]?
        let forbidPlaceholderMarker: Bool?

        enum CodingKeys: String, CodingKey {
            case voiceProfile = "voice_profile"
            case requiredAssets = "required_assets"
            case forbiddenSubstrings = "forbidden_substrings"
            case forbidPlaceholderMarker = "forbid_placeholder_marker"
        }
    }

    private struct VoiceProfileEntry: Decodable {
        let relativePath: String
        let requiredPersonaID: String?

        enum CodingKeys: String, CodingKey {
            case relativePath = "relative_path"
            case requiredPersonaID = "required_persona_id"
        }
    }

    private struct RequiredAssetEntry: Decodable {
        let label: String
        let relativePath: String
        let minBytes: UInt64
        let sha256: String?

        enum CodingKeys: String, CodingKey {
            case label
            case relativePath = "relative_path"
            case minBytes = "min_bytes"
            case sha256
        }
    }

    private static let manifestRelativePath = "cells/franklin/avatar/required_assets.json"

    // MARK: - Public API

    static func evaluate() -> FranklinLaunchGateResult {
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let manifestURL = cursor.appendingPathComponent(manifestRelativePath)
            // #region agent log
            FranklinDebugLogger.log(
                runId: "pre-fix",
                hypothesisId: "H1",
                location: "FranklinLaunchGate.swift:evaluate",
                message: "Probe workspace for launch manifest",
                data: [
                    "cursor": cursor.path,
                    "manifestExists": String(fm.fileExists(atPath: manifestURL.path)),
                ]
            )
            // #endregion
            if fm.fileExists(atPath: manifestURL.path) {
                return evaluate(workspaceRoot: cursor, manifestURL: manifestURL)
            }
            // Also accept the gaiaFTCL marker so we walk up out of GAIAOS/macos/Franklin.
            let marker = cursor.appendingPathComponent("gaiaFTCL", isDirectory: true)
            if fm.fileExists(atPath: marker.path) {
                cursor = marker
                continue
            }
            cursor.deleteLastPathComponent()
        }
        return FranklinLaunchGateResult(
            ready: false,
            refusals: ["GW_REFUSE_AVATAR_WORKSPACE_ROOT_UNRESOLVED"]
        )
    }

    /// Test-friendly entry point. Pass an explicit workspace root + manifest URL.
    static func evaluate(workspaceRoot: URL, manifestURL: URL) -> FranklinLaunchGateResult {
        let manifest: RequiredAssetsManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(RequiredAssetsManifest.self, from: data)
        } catch {
            return FranklinLaunchGateResult(
                ready: false,
                refusals: ["GW_REFUSE_AVATAR_REQUIRED_ASSETS_JSON_MISSING"]
            )
        }

        let placeholderEnforced = manifest.forbidPlaceholderMarker ?? false
        let forbiddenSubstrings = manifest.forbiddenSubstrings ?? []

        var failures: [String] = []
        for entry in manifest.requiredAssets {
            let url = workspaceRoot.appendingPathComponent(entry.relativePath)
            guard let size = fileSize(url.path) else {
                failures.append("GW_REFUSE_ASSET_MISSING:\(entry.label)")
                // #region agent log
                FranklinDebugLogger.log(
                    runId: "pre-fix",
                    hypothesisId: "H5",
                    location: "FranklinLaunchGate.swift:requiredAssetsLoop",
                    message: "Required asset missing",
                    data: [
                        "label": entry.label,
                        "path": url.path,
                    ]
                )
                // #endregion
                continue
            }
            if size < entry.minBytes {
                failures.append("GW_REFUSE_ASSET_TOO_SMALL:\(entry.label)")
                // #region agent log
                FranklinDebugLogger.log(
                    runId: "pre-fix",
                    hypothesisId: "H5",
                    location: "FranklinLaunchGate.swift:requiredAssetsLoop",
                    message: "Required asset undersized",
                    data: [
                        "label": entry.label,
                        "path": url.path,
                        "size": String(size),
                        "minBytes": String(entry.minBytes),
                    ]
                )
                // #endregion
                continue
            }
            if let pinned = entry.sha256, !pinned.isEmpty {
                if let actual = fileSHA256Hex(url.path), actual != pinned {
                    failures.append("GW_REFUSE_ASSET_HASH_MISMATCH:\(entry.label)")
                    continue
                }
            }
            // Anti-placeholder enforcement (cancer prevention). Even if a file
            // satisfies size + hash, it cannot ship if it carries a dev_stub /
            // placeholder marker. The build script enforces the same rule.
            if placeholderEnforced,
               let needle = firstForbiddenSubstring(at: url.path, against: forbiddenSubstrings) {
                failures.append("GW_REFUSE_ASSET_PLACEHOLDER_MARKER:\(entry.label)(found:\(needle))")
                // #region agent log
                FranklinDebugLogger.log(
                    runId: "pre-fix",
                    hypothesisId: "H5",
                    location: "FranklinLaunchGate.swift:requiredAssetsLoop",
                    message: "Placeholder marker detected",
                    data: [
                        "label": entry.label,
                        "path": url.path,
                        "needle": needle,
                    ]
                )
                // #endregion
            }
        }

        if let vp = manifest.voiceProfile {
            let vpURL = workspaceRoot.appendingPathComponent(vp.relativePath)
            if let data = try? Data(contentsOf: vpURL),
               let profile = try? JSONDecoder().decode(FranklinVoiceProfile.self, from: data) {
                if let required = vp.requiredPersonaID, profile.personaID != required {
                    failures.append("GW_REFUSE_FRANKLIN_VOICE_PROFILE_INVALID_PERSONA")
                }
            } else {
                failures.append("GW_REFUSE_FRANKLIN_VOICE_PROFILE_MISSING")
            }
        }

        // #region agent log
        FranklinDebugLogger.log(
            runId: "pre-fix",
            hypothesisId: "H1",
            location: "FranklinLaunchGate.swift:evaluate(workspaceRoot:manifestURL:)",
            message: "Launch gate contract result",
            data: [
                "workspaceRoot": workspaceRoot.path,
                "assetCount": String(manifest.requiredAssets.count),
                "failureCount": String(failures.count),
                "ready": String(failures.isEmpty),
                "firstFailure": failures.first ?? "none",
            ]
        )
        // #endregion

        return FranklinLaunchGateResult(ready: failures.isEmpty, refusals: failures)
    }

    // MARK: - Helpers

    private static func fileSize(_ path: String) -> UInt64? {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? UInt64
        else { return nil }
        return size
    }

    /// Returns the first forbidden substring found in the file's first 64 KB
    /// (where placeholder markers always sit), or nil if none match. Reads at
    /// most 64 KB so the check is bounded even on multi-GB mesh blobs.
    private static func firstForbiddenSubstring(at path: String, against needles: [String]) -> String? {
        guard !needles.isEmpty,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let probe: Data
        if #available(macOS 10.15, *) {
            probe = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        } else {
            probe = handle.readData(ofLength: 64 * 1024)
        }
        guard !probe.isEmpty else { return nil }
        let probeString = String(data: probe, encoding: .utf8)
            ?? String(data: probe, encoding: .ascii)
            ?? ""
        for needle in needles where !needle.isEmpty {
            if probeString.contains(needle) { return needle }
        }
        return nil
    }

    /// Streaming SHA-256 so the gate doesn't pull a 1.5 M-tri mesh fully into RAM.
    /// Returns nil only when the file cannot be opened.
    private static func fileSHA256Hex(_ path: String) -> String? {
        guard let stream = InputStream(fileAtPath: path) else { return nil }
        stream.open()
        defer { stream.close() }
        var ctx = SHA256Context()
        let bufSize = 64 * 1024
        var buf = [UInt8](repeating: 0, count: bufSize)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: bufSize)
            if n <= 0 { break }
            ctx.update(buf, count: n)
        }
        return ctx.finalizeHex()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHA-256 implementation kept inside the launch gate so the runtime gate has
// no Crypto dependency the build plugin doesn't also have. This is small and
// self-contained; it is NOT used for FUIT signing — that path uses Ed25519
// via swift-crypto.
// ─────────────────────────────────────────────────────────────────────────────

private struct SHA256Context {
    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    private var buffer: [UInt8] = []
    private var totalBytes: UInt64 = 0

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    mutating func update(_ bytes: [UInt8], count: Int) {
        totalBytes &+= UInt64(count)
        buffer.append(contentsOf: bytes.prefix(count))
        while buffer.count >= 64 {
            let block = Array(buffer.prefix(64))
            buffer.removeFirst(64)
            compress(block)
        }
    }

    mutating func finalizeHex() -> String {
        let bitLen = totalBytes &* 8
        buffer.append(0x80)
        while buffer.count % 64 != 56 { buffer.append(0x00) }
        for i in (0..<8).reversed() { buffer.append(UInt8((bitLen >> (UInt64(i) * 8)) & 0xff)) }
        while buffer.count >= 64 {
            let block = Array(buffer.prefix(64))
            buffer.removeFirst(64)
            compress(block)
        }
        var out = ""
        for w in state {
            out += String(format: "%08x", w)
        }
        return out
    }

    private mutating func compress(_ block: [UInt8]) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            w[i] = (UInt32(block[i*4]) << 24) | (UInt32(block[i*4+1]) << 16) | (UInt32(block[i*4+2]) << 8) | UInt32(block[i*4+3])
        }
        for i in 16..<64 {
            let s0 = rotr(w[i-15], 7) ^ rotr(w[i-15], 18) ^ (w[i-15] >> 3)
            let s1 = rotr(w[i-2], 17) ^ rotr(w[i-2], 19) ^ (w[i-2] >> 10)
            w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
        }
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for i in 0..<64 {
            let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let t1 = h &+ S1 &+ ch &+ Self.k[i] &+ w[i]
            let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let mj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = S0 &+ mj
            h = g; g = f; f = e; e = d &+ t1
            d = c; c = b; b = a; a = t1 &+ t2
        }
        state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
    }

    private func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        return (x >> n) | (x << (32 - n))
    }
}
