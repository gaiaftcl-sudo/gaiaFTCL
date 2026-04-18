import Foundation
import os

struct TelemetrySnapshot: Sendable {
    var ip: Double = 0.0
    var bt: Double = 0.0
    var ne: Double = 0.0
    var epistemicClass: Int = 0
    /// Measurement-classification tags (M/T/I/A) per variable.
    var tagIp: String = "M"
    var tagBt: String = "M"
    var tagNe: String = "M"
}

final class UIStateManifold: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var state = TelemetrySnapshot()

    func clobberState(
        ip: Double,
        bt: Double,
        ne: Double,
        epistemicClass: Int,
        tagIp: String = "M",
        tagBt: String = "M",
        tagNe: String = "M"
    ) {
        os_unfair_lock_lock(&lock)
        state.ip = ip
        state.bt = bt
        state.ne = ne
        state.epistemicClass = epistemicClass
        state.tagIp = tagIp
        state.tagBt = tagBt
        state.tagNe = tagNe
        os_unfair_lock_unlock(&lock)
    }

    func readLatest() -> TelemetrySnapshot {
        os_unfair_lock_lock(&lock)
        let snapshot = state
        os_unfair_lock_unlock(&lock)
        return snapshot
    }
}
