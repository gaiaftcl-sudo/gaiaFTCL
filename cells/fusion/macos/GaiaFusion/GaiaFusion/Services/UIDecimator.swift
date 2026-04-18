import Foundation

@MainActor
final class UIDecimator {
    private let manifold: UIStateManifold
    private weak var bridge: FusionBridge?
    private var timer: Timer?

    init(manifold: UIStateManifold, bridge: FusionBridge) {
        self.manifold = manifold
        self.bridge = bridge
    }

    func start(fps: Double = 30.0) {
        stop()
        let interval = 1.0 / max(1.0, fps)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pumpToWasm()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pumpToWasm() {
        let snapshot = manifold.readLatest()
        bridge?.emitUITelemetrySync(snapshot: snapshot)
    }
}
