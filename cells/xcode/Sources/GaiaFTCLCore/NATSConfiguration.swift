import Foundation

/// Sovereign NATS URL registry — **C4** (vQbit VM / substrate) vs **S4** (Franklin introspection bus).
/// Single-broker dev: set **`GAIAFTCL_FRANKLIN_NATS_URL`** to the same URL as **`GAIAFTCL_VQBIT_NATS_URL`** (or legacy **`GAIAFTCL_NATS_URL`**).
public enum NATSConfiguration {
    /// **C4 cell** — vQbit VM. Subjects `gaiaftcl.substrate.*`. Measurement + mesh gateway boundary.
    public static var vqbitNATSURL: String {
        if let u = ProcessInfo.processInfo.environment["GAIAFTCL_VQBIT_NATS_URL"], !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return u.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let legacy = ProcessInfo.processInfo.environment["GAIAFTCL_NATS_URL"], !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "nats://127.0.0.1:4222"
    }

    /// **S4 cell** — Franklin. Subjects `gaiaftcl.franklin.*`. Authorship + calibration; not the **M⁸** instrument.
    public static var franklinNATSURL: String {
        if let u = ProcessInfo.processInfo.environment["GAIAFTCL_FRANKLIN_NATS_URL"], !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return u.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "nats://127.0.0.1:4223"
    }

    // MARK: - NATS subjects (canonical sovereign M8 wire)

    public static let tauSubject                   = "gaiaftcl.mesh.tau"
    public static let vmReadySubject               = "gaiaftcl.vm.ready"
    public static let vmHeartbeatSubject           = "gaiaftcl.vm.heartbeat"
    public static let franklinStageMooredSubject   = "gaiaftcl.franklin.stage.moored"
    public static let franklinStageUnmooredSubject = "gaiaftcl.franklin.stage.unmoored"
    public static let franklinMooredSubject        = "gaiaftcl.franklin.moored"
    public static let s4DeltaSubject               = "gaiaftcl.substrate.s4.delta"
    public static let c4ProjectionSubject          = "gaiaftcl.substrate.c4.projection"
    public static let meshTauSubject               = "gaiaftcl.mesh.tau"

    /// s3_spatial from CoreLocation accuracy: 1 − (accuracy_m / 10_000), clamped [0, 1].
    public static func s3Spatial(accuracyMeters: Double) -> Double {
        min(max(1.0 - (accuracyMeters / 10_000.0), 0.0), 1.0)
    }
}
