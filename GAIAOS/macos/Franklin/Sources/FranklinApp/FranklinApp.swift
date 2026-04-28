import SwiftUI
import FranklinUIKit

@main
struct FranklinAppMain: App {
    @State private var showCanvas = false
    @StateObject private var model = OperatorSurfaceModel()
    private let launchGate = FranklinLaunchGate.evaluate()

    init() {
        SproutEvidenceCoordinator.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup("Franklin") {
            if launchGate.ready {
                CanvasView()
                    .environmentObject(model)
            } else {
                FranklinLaunchRefusalView(refusals: launchGate.refusals)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 620)

        WindowGroup("Franklin Avatar Presence") {
            if launchGate.ready {
                AvatarView(showCanvas: $showCanvas)
                    .environmentObject(model)
                    .frame(width: 120, height: 120)
                    .background(Color.clear)
            } else {
                FranklinLaunchRefusalDot()
                    .frame(width: 120, height: 120)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 120, height: 120)
    }
}

private struct FranklinLaunchRefusalView: View {
    let refusals: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Franklin Avatar Refused")
                .font(.title2.bold())
                .foregroundStyle(.red)
            Text("Launch gate blocked. Required Passy assets/voice are not present.")
                .font(.system(size: 13, weight: .semibold))
            ForEach(Array(refusals.prefix(6).enumerated()), id: \.offset) { _, refusal in
                Text(refusal)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(20)
    }
}

private struct FranklinLaunchRefusalDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.25))
            Image(systemName: "xmark.seal.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.red)
        }
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
