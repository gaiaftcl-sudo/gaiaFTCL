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
    @State private var c4Sub    = LocalC4Subscriber()

    var body: some Scene {
        WindowGroup("GaiaFTCL — Sovereign M\u{2078}") {
            FranklinSceneView()
                .environment(director)
                .environment(store)
                .environment(overlay)
                .modelContainer(for: CachedSceneEntry.self)
                .onAppear { c4Sub.start(overlay: overlay) }
        }
        .defaultSize(width: 960, height: 620)
    }
}
