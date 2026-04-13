import Foundation

@MainActor
final class UITelemetryThrottler {
    private weak var bridge: FusionBridge?
    private var timer: Timer?
    private var latestValues: [String: Double] = [:]
    private var latestClasses: [String: Int] = [:]

    init(bridge: FusionBridge) {
        self.bridge = bridge
    }

    func updateLatestState(values: [String: Double], classes: [String: Int]) {
        latestValues.merge(values) { _, new in new }
        latestClasses.merge(classes) { _, new in new }
    }

    func start(fps: Double = 30.0) {
        stop()
        let interval = 1.0 / max(1.0, fps)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.emitToWasm()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func emitToWasm() {
        guard let bridge else { return }
        bridge.sendDirect(
            action: "UI_TELEMETRY_SYNC",
            data: [
                "I_p": latestValues["I_p"] ?? 0.0,
                "B_T": latestValues["B_T"] ?? 0.0,
                "n_e": latestValues["n_e"] ?? 0.0,
                "class_I_p": latestClasses["I_p"] ?? 0,
                "class_B_T": latestClasses["B_T"] ?? 0,
                "class_n_e": latestClasses["n_e"] ?? 0,
            ]
        )
    }
}
