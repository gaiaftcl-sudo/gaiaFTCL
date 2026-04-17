// ContentView.swift — MacHealth
// Displays BioState, M/I/A epistemic tag, and Metal renderer status

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BioStateViewModel()

    var body: some View {
        HSplitView {
            // Left panel: cell state
            VStack(alignment: .leading, spacing: 12) {
                Text("GaiaHealth Biologit Cell")
                    .font(.headline)
                    .padding(.top)

                EpistemicBadge(tag: viewModel.epistemicTag)

                Divider()

                Text("State: \(viewModel.stateName)")
                    .font(.system(.body, design: .monospaced))

                Text("Frame: \(viewModel.frameCount)")
                    .font(.system(.body, design: .monospaced))

                Text("PII Stored: false")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Advance State") {
                    viewModel.advance()
                }
                .padding(.bottom)
            }
            .frame(minWidth: 200, maxWidth: 240)
            .padding()

            // Right panel: Metal renderer canvas
            MetalHealthView(viewModel: viewModel)
                .frame(minWidth: 560)
        }
        .onAppear { viewModel.initialize() }
    }
}

struct EpistemicBadge: View {
    let tag: UInt32
    var body: some View {
        let (label, color): (String, Color) = switch tag {
            case 0: ("M — Measured", .blue)
            case 1: ("I — Inferred", .green)
            case 2: ("A — Assumed",  .orange)
            default: ("? — Unknown", .red)
        }
        Text(label)
            .font(.system(.body, design: .monospaced).bold())
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }
}
