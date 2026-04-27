import SwiftUI
import FranklinUIKit

@main
struct FranklinAppMain: App {
    @State private var showCanvas = false
    @StateObject private var model = OperatorSurfaceModel()

    init() {
        SproutEvidenceCoordinator.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup("Franklin Orb") {
            OrbView(showCanvas: $showCanvas)
                .environmentObject(model)
                .frame(width: 120, height: 120)
                .background(Color.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 120, height: 120)

        WindowGroup("Franklin Canvas") {
            CanvasView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 620)
    }
}

struct OrbView: View {
    @Binding var showCanvas: Bool
    @EnvironmentObject var model: OperatorSurfaceModel
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(FranklinGlass.orb)
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
