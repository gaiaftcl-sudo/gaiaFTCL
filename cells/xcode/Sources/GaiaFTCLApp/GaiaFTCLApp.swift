import SwiftUI
import SwiftData
import GaiaFTCL
import GaiaFTCLScene
import GaiaFTCLCore

@main
struct GaiaFTCLApp: App {
    @State private var director = FranklinSceneDirector()
    @State private var store    = VQbitStore()
    @State private var overlay  = ManifoldOverlayStore()
    @State private var launcher = SovereignStackLauncher()

    var body: some Scene {
        // Sovereign instrument — single non-restorable window.
        Window("GaiaFTCL — Sovereign M\u{2078}", id: "main") {
            Group {
                if case .ready = launcher.phase {
                    FranklinSceneView()
                        .environment(director)
                        .environment(store)
                        .environment(overlay)
                } else {
                    StackLaunchView(launcher: launcher)
                }
            }
            .modelContainer(for: CachedSceneEntry.self)
            .onAppear {
                Task { await launcher.launch(overlay: overlay) }
            }
            .onDisappear {
                launcher.teardown()
            }
        }
        .defaultSize(width: 960, height: 620)

        // Domain portal windows — wired to openWindow(id: "domain-fusion") in FranklinSceneView.
        Window("Fusion Domain — M\u{2078}", id: "domain-fusion") {
            DomainPortalView(domain: "fusion", title: "Fusion — Sovereign C4")
                .environment(overlay)
        }
        .defaultSize(width: 480, height: 320)

        Window("Health Domain — M\u{2078}", id: "domain-health") {
            DomainPortalView(domain: "health", title: "Health — Constitutional Threshold")
                .environment(overlay)
        }
        .defaultSize(width: 480, height: 320)
    }
}

/// Minimal domain portal — shows live C4 telemetry for a given domain.
private struct DomainPortalView: View {
    let domain: String
    let title:  String
    @Environment(ManifoldOverlayStore.self) private var overlay

    private static let bg = Color(red: 0.03, green: 0.04, blue: 0.12)

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.cyan)
            Divider().overlay(.cyan.opacity(0.3))
            let s = overlay.current
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                row("c1 trust",       s.c1_trust)
                row("c2 identity",    s.c2_identity)
                row("c3 closure",     s.c3_closure)
                row("c4 consequence", s.c4_consequence)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85))
            Text(s.terminalState.rawValue)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(terminalColor(s.terminalState))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.bg)
    }

    private func row(_ label: String, _ value: Double) -> some View {
        GridRow {
            Text(label).foregroundStyle(.white.opacity(0.5))
            Text(String(format: "%.4f", value))
        }
    }

    private func terminalColor(_ t: TerminalState) -> Color {
        switch t {
        case .calorie: .cyan
        case .cure:    .orange
        case .refused: .red
        case .blocked: .purple
        }
    }
}
