import SwiftUI

/// Placeholder plant control panel stub
private struct PlantControlPanel: View {
    let plantKind: String
    @ObservedObject var playback: MetalPlaybackController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plant Controls")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            
            // Placeholder for plant-specific controls
            Text("[\(plantKind) parameters]")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
    }
}

/// Left sidebar control panel for fusion plant parameters
/// Fixed width: 285pt per GaiaFusion_Layout_Spec.md
struct FusionControlSidebar: View {
    let plantKind: String
    @ObservedObject var playback: MetalPlaybackController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Plant topology header
            Text(plantKind.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            
            // Plant control panel
            PlantControlPanel(plantKind: plantKind, playback: playback)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            
            Spacer()
        }
        .frame(width: 285)
        .background(Color.black.opacity(0.85))
    }
}
