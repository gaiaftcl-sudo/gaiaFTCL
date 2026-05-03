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
}
