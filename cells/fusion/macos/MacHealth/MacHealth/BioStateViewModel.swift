// BioStateViewModel.swift — MacHealth
import Foundation
import SwiftUI
import GaiaHealthRenderer

@MainActor
final class BioStateViewModel: ObservableObject {
    @Published var epistemicTag: UInt32 = 2    // Assumed
    @Published var frameCount:   UInt64 = 0
    @Published var stateName:    String = "IDLE"

    nonisolated(unsafe) private var rendererHandle: GaiaHealthRendererHandle? = nil
    nonisolated(unsafe) private var timer: Timer?

    func initialize() {
        rendererHandle = gaia_health_renderer_create()
        // Start 30fps tick
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        guard let handle = rendererHandle else { return }
        gaia_health_renderer_tick_frame(handle)
        frameCount   = gaia_health_renderer_get_frame_count(handle)
        epistemicTag = gaia_health_renderer_get_epistemic(handle)
    }

    func advance() {
        guard let handle = rendererHandle else { return }
        let next = (epistemicTag + 1) % 3
        gaia_health_renderer_set_epistemic(handle, next)
        epistemicTag = next
        let names = ["IDLE", "MOORED", "PREPARED", "RUNNING", "ANALYSIS", "CURE"]
        let idx = min(Int(next), names.count - 1)
        stateName = names[idx]
    }

    deinit {
        timer?.invalidate()
        if let handle = rendererHandle {
            gaia_health_renderer_destroy(handle)
        }
    }
}
