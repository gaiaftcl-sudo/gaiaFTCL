import SwiftUI

struct StatusBarView: View {
    @ObservedObject var meshManager: MeshStateManager
    let isTraceLayerActive: Bool

    private var statusColor: Color {
        // Ten mesh nodes: nine fleet + local GaiaFusion leaf (see MeshStateManager.MeshConstants.meshNodeCount).
        switch meshManager.healthyCount {
        case MeshStateManager.MeshConstants.meshNodeCount:
            return .green
        case 6 ... 9:
            return .yellow
        default:
            return .red
        }
    }

    private var natsText: String {
        meshManager.natsConnected ? "connected" : "disconnected"
    }

    private var natsColor: Color {
        meshManager.natsConnected ? .green : .red
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(isTraceLayerActive ? "Trace Layer Active" : "Clean Surface")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isTraceLayerActive ? .orange : .green)
                Divider()
                Text("Mesh: \(meshManager.meshHealthText)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Divider()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("NATS:")
                Text(natsText)
                    .foregroundStyle(natsColor)
                Divider()
                Text(String(format: "vQbit (local mesh): %.3f", meshManager.vQbit))
                    .help("Local ratio healthy/\(MeshStateManager.MeshConstants.meshNodeCount); substrate-sealed vQbit requires gateway ingest (see MAC_CELL_MOORING_AND_VQBIT.md).")
            }
            .padding(.horizontal, 10)
            Spacer()
            Text("GaiaFTCL v1.0")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, minHeight: 24)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .foregroundStyle(.white)
    }
}
