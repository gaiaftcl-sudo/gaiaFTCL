import Foundation
import GaiaFTCLCore

#if os(macOS)
/// **τ** freshness + **cell_identity** mooring (IQ-ARCH-005 / IQ-ARCH-006).
public enum SovereignCellIQGate {
    public static let skipEnv = "GAIAFTCL_IQ_SKIP_SOVEREIGN_CELL"
    public static let strictEnv = "GAIAFTCL_IQ_STRICT_SOVEREIGN"

    /// **Opt-in** IQ-ARCH-005/006: set **`GAIAFTCL_IQ_STRICT_SOVEREIGN=1`** to require `tau_sync_state.json` + `cell_identity.json`.
    public static func verify() -> [String] {
        if ProcessInfo.processInfo.environment[skipEnv] == "1" {
            return []
        }
        if ProcessInfo.processInfo.environment[strictEnv] != "1" {
            return []
        }
        var errs: [String] = []
        errs.append(contentsOf: verifyTauFresh())
        errs.append(contentsOf: verifyMooringIdentity())
        return errs
    }

    private static func verifyTauFresh() -> [String] {
        let url = GaiaInstallPaths.tauSyncStateURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [
                "[IQ] tau_sync_state.json missing — start VQbitVM (self-fetch τ via HTTPS; mesh gaiaftcl.mesh.tau accepted when present)",
            ]
        }
        guard let iso = obj["received_at_iso"] as? String else {
            return ["[IQ] tau_sync_state.json missing received_at_iso"]
        }
        let fmt = ISO8601DateFormatter()
        guard let received = fmt.date(from: iso) else {
            return ["[IQ] tau_sync_state.json invalid received_at_iso"]
        }
        let age = Date().timeIntervalSince(received)
        if age > NATSConfiguration.tauStalenessSeconds {
            return [
                "[IQ] τ stale: \(Int(age))s > \(Int(NATSConfiguration.tauStalenessSeconds))s — IQ-ARCH-005 failed",
            ]
        }
        return []
    }

    private static func verifyMooringIdentity() -> [String] {
        let url = GaiaInstallPaths.cellIdentityURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ["[IQ] cell_identity.json missing — Franklin Location mooring not sealed (IQ-ARCH-006)"]
        }
        let lat = obj["latitude"] as? Double
        let lon = obj["longitude"] as? Double
        let s3 = obj["s3_spatial"] as? Double
        guard let lat, let lon else {
            return ["[IQ] cell_identity.json missing latitude/longitude"]
        }
        if abs(lat) < 1e-9 && abs(lon) < 1e-9 {
            return ["[IQ] cell_identity lat/lon are zero — not moored"]
        }
        guard let s3, s3 > 0 else {
            return ["[IQ] cell_identity s3_spatial must be > 0 — IQ-ARCH-006"]
        }
        return []
    }
}
#endif
