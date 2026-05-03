import SwiftUI
import FranklinUIKit

@main
struct FranklinAppMain: App {
    @State private var showCanvas = false
    @StateObject private var model = OperatorSurfaceModel()
    @State private var phaseModel = AppPhaseModel()
    private let configuration = FranklinAppConfiguration.load()
    private let startupGateProbe = FranklinLaunchGate.evaluate()

    init() {
        SproutEvidenceCoordinator.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup("Franklin") {
            switch phaseModel.phase {
            case .preparing:
                FranklinPreparingView()
                    .task { await phaseModel.bootstrap() }
            case .avatarWake:
                FranklinAvatarWakeView()
                    .environmentObject(model)
            case .operatorSurface:
                CanvasView()
                    .environmentObject(model)
            case .failed(let refusals):
                FranklinLaunchRefusalView(refusals: refusals, showTechnicalDiagnostics: configuration.showTechnicalDiagnostics)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 620)

        WindowGroup("Franklin Avatar Presence") {
            AvatarView(showCanvas: $showCanvas)
                .environmentObject(model)
                .frame(width: 120, height: 120)
                .background(Color.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 120, height: 120)
    }
}

private struct FranklinPreparingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Preparing Franklin avatar substrate...")
                .font(.system(size: 13, weight: .semibold))
            Text("Verifying Passy mesh, voice manifest, and render contract.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private struct FranklinAvatarWakeView: View {
    @EnvironmentObject var model: OperatorSurfaceModel

    var body: some View {
        VStack(spacing: 12) {
            FranklinAvatarStage()
                .environmentObject(model)
            Text("Franklin avatar waking...")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct FranklinLaunchRefusalView: View {
    let refusals: [String]
    let showTechnicalDiagnostics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Franklin Startup Needs Attention")
                .font(.title2.bold())
                .foregroundStyle(.orange)
            Text("Franklin remains in guided startup mode while runtime dependencies are verified.")
                .font(.system(size: 13, weight: .semibold))
            if showTechnicalDiagnostics {
                ForEach(Array(refusals.prefix(6).enumerated()), id: \.offset) { _, refusal in
                    Text(refusal)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Technical diagnostics are hidden from operator UI. Use logs/pipeline reports for details.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }
}

struct AvatarView: View {
    @Binding var showCanvas: Bool
    @EnvironmentObject var model: OperatorSurfaceModel
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(FranklinGlass.avatar)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.45), lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .fill(model.lastResult.hasPrefix("REFUSED") ? Color.red.opacity(0.28) : Color.green.opacity(0.18))
                )
                .scaleEffect(1 + (sin(phase) * 0.04))
                .animation(.franklin, value: phase)
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .background(Color.black.opacity(0.001))
        .onTapGesture {
            showCanvas = true
            NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
        }
        .task {
            while true {
                phase += 0.8
                await model.refreshStatus()
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
    }
}
