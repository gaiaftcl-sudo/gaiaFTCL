import Foundation

struct FranklinLaunchGateResult {
    let ready: Bool
    let refusals: [String]
}

enum FranklinLaunchGate {
    private struct RequiredAsset {
        let label: String
        let relativePath: String
        let minBytes: UInt64
    }

    static func evaluate() -> FranklinLaunchGateResult {
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let failures = evaluateAtRoot(cursor)
            if !failures.isEmpty || fm.fileExists(atPath: cursor.appendingPathComponent("gaiaFTCL").path) {
                return FranklinLaunchGateResult(ready: failures.isEmpty, refusals: failures)
            }
            cursor.deleteLastPathComponent()
        }
        return FranklinLaunchGateResult(
            ready: false,
            refusals: ["GW_REFUSE_AVATAR_WORKSPACE_ROOT_UNRESOLVED"]
        )
    }

    private static func evaluateAtRoot(_ root: URL) -> [String] {
        var failures: [String] = []
        for required in requiredAssets() {
            let path = root.appendingPathComponent(required.relativePath)
            guard let size = fileSize(path.path) else {
                failures.append("GW_REFUSE_ASSET_MISSING:\(required.label)")
                continue
            }
            if size < required.minBytes {
                failures.append("GW_REFUSE_ASSET_TOO_SMALL:\(required.label)")
            }
        }

        let voiceProfilePath = root.appendingPathComponent(
            "cells/franklin/avatar/bundle_assets/voice/franklin_voice_profile.json"
        )
        guard
            let data = try? Data(contentsOf: voiceProfilePath),
            let profile = try? JSONDecoder().decode(FranklinVoiceProfile.self, from: data)
        else {
            failures.append("GW_REFUSE_FRANKLIN_VOICE_PROFILE_MISSING")
            return failures
        }
        if profile.personaID != "franklin.guide.v1" {
            failures.append("GW_REFUSE_FRANKLIN_VOICE_PROFILE_INVALID_PERSONA")
        }
        return failures
    }

    private static func requiredAssets() -> [RequiredAsset] {
        [
            RequiredAsset(
                label: "Franklin_Passy_V2.fblob",
                relativePath: "cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.fblob",
                minBytes: 1_000_000
            ),
            RequiredAsset(
                label: "Franklin_Z3_Materials.metallib",
                relativePath: "cells/franklin/avatar/bundle_assets/materials/Franklin_Z3_Materials.metallib",
                minBytes: 50_000
            ),
            RequiredAsset(
                label: "beaver_cap_spectral_lut.exr",
                relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/beaver_cap_spectral_lut.exr",
                minBytes: 10_000
            ),
            RequiredAsset(
                label: "anisotropic_flow_map.exr",
                relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/anisotropic_flow_map.exr",
                minBytes: 10_000
            ),
            RequiredAsset(
                label: "claret_silk_degradation.exr",
                relativePath: "cells/franklin/avatar/bundle_assets/spectral_luts/claret_silk_degradation.exr",
                minBytes: 10_000
            ),
            RequiredAsset(
                label: "styletts2_franklin_v1.coreml.mlmodelc/Manifest.json",
                relativePath: "cells/franklin/avatar/bundle_assets/voice/styletts2_franklin_v1.coreml.mlmodelc/Manifest.json",
                minBytes: 100
            ),
        ]
    }

    private static func fileSize(_ path: String) -> UInt64? {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? UInt64
        else { return nil }
        return size
    }
}
