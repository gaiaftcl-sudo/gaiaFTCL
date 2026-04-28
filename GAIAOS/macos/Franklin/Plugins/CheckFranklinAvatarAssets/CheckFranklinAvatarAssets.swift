// ─────────────────────────────────────────────────────────────────────────────
// CheckFranklinAvatarAssets.swift
//
// SwiftPM build-tool plugin. Invoked by `swift build` and Xcode's build phase
// for any target that lists this plugin. Runs the canonical
// scripts/check_franklin_avatar_assets.zsh against the workspace root and
// fails the build with `GW_REFUSE_ASSET_*` diagnostics when any required
// Passy asset is missing, undersized, or hash-mismatched.
//
// Contract: scripts/check_franklin_avatar_assets.zsh +
//           cells/franklin/avatar/required_assets.json +
//           Sources/FranklinApp/FranklinLaunchGate.swift
// ─────────────────────────────────────────────────────────────────────────────

import PackagePlugin
import Foundation

@main
struct CheckFranklinAvatarAssets: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Walk up from the package directory until we find gaiaFTCL/.
        let pkg = context.package.directoryURL
        var cursor = pkg
        var workspace: URL?
        for _ in 0..<8 {
            let direct = cursor.appendingPathComponent("cells/franklin/avatar/required_assets.json")
            if FileManager.default.fileExists(atPath: direct.path) {
                workspace = cursor
                break
            }

            let nested = cursor
                .appendingPathComponent("gaiaFTCL", isDirectory: true)
                .appendingPathComponent("cells/franklin/avatar/required_assets.json")
            if FileManager.default.fileExists(atPath: nested.path) {
                workspace = cursor.appendingPathComponent("gaiaFTCL", isDirectory: true)
                break
            }
            cursor = cursor.deletingLastPathComponent()
        }
        guard let workspaceRoot = workspace else {
            Diagnostics.error("""
                CheckFranklinAvatarAssets: could not locate workspace root containing
                cells/franklin/avatar/required_assets.json. Run `swift build` from inside
                the gaiaFTCL repository tree.
                Refusal: GW_REFUSE_AVATAR_WORKSPACE_ROOT_UNRESOLVED
                """)
            // Returning no commands lets the build proceed only if the diag is non-fatal.
            // We make it fatal by emitting a phony command that always fails.
            return [makePhonyFailCommand(reason: "GW_REFUSE_AVATAR_WORKSPACE_ROOT_UNRESOLVED")]
        }

        let script = workspaceRoot.appendingPathComponent("scripts/check_franklin_avatar_assets.zsh")
        let manifest = workspaceRoot.appendingPathComponent("cells/franklin/avatar/required_assets.json")
        let stamp = context.pluginWorkDirectoryURL.appendingPathComponent("franklin_avatar_assets.stamp")

        // The plugin output (stamp file) depends on the manifest and the script.
        // Whenever either changes, the gate re-runs. Whenever any required asset
        // is missing, the gate exits non-zero and the build fails.
        return [
            .prebuildCommand(
                displayName: "Check Franklin avatar assets (Passy gate)",
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [
                    script.path,
                    workspaceRoot.path,
                ],
                environment: [
                    "FRANKLIN_AVATAR_GATE_STAMP": stamp.path,
                    "FRANKLIN_AVATAR_GATE_MANIFEST": manifest.path,
                ],
                outputFilesDirectory: context.pluginWorkDirectoryURL
            )
        ]
    }

    private func makePhonyFailCommand(reason: String) -> Command {
        // A pre-build command that always fails — used when the workspace root
        // cannot be resolved at all.
        return .prebuildCommand(
            displayName: "Franklin avatar gate refused: \(reason)",
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: [],
            outputFilesDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
    }
}
