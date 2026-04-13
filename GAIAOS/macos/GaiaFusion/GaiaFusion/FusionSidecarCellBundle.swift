import Foundation

/// Docker MCP **cell** assets shipped inside the composite app bundle — distinct from the native Fusion surface (Swift/Metal/web).
enum FusionSidecarCellBundle {
    private static let subdir = "fusion-sidecar-cell"

    /// C4-honest payload for `/api/fusion/health`: Fusion is native; **bundled** compose is the Mac full-cell substrate package (operators run it for :8803 in-loop verification).
    static func healthPayload() -> [String: Any] {
        let compose = bundledComposeURL()
        return [
            "fusion_surface": "native_swift",
            "cell_substrate": "docker_compose_bundled_full_cell",
            "bundled_cell_compose_present": compose != nil,
            "bundled_compose_bundle_path": compose?.path as Any,
            "mac_full_cell_note": "GaiaFusion ships fusion-sidecar-cell/docker-compose.fusion-sidecar.yml for the local MCP gateway cell; production loop verification probes 127.0.0.1:8803 alongside the nine WAN cells.",
        ]
    }

    /// Canonical `docker-compose.fusion-sidecar.yml` inside the app resources (if packaged).
    static func bundledComposeURL() -> URL? {
        Bundle.module.url(
            forResource: "docker-compose.fusion-sidecar",
            withExtension: "yml",
            subdirectory: subdir
        )
    }
}
