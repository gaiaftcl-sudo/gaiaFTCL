import Foundation

/// Stable cell UUID for binary logs (**override** with **`GAIAFTCL_CELL_ID`** env).
public enum GaiaCellIdentity {
    public static var uuid: UUID {
        if let s = ProcessInfo.processInfo.environment["GAIAFTCL_CELL_ID"],
           let u = UUID(uuidString: s.trimmingCharacters(in: .whitespacesAndNewlines)), !s.isEmpty {
            return u
        }
        return UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    }
}

/// Alias used by qualification harnesses (**current cell id**).
public enum CellIdentity {
    public static var current: UUID { GaiaCellIdentity.uuid }
}

/// Single canonical IQ path for `FranklinConsciousnessService` after Option A install.
/// Must match `GAIAFTCL_SERVICE_BINARY_PATH` in `scripts/install_franklin_consciousness_service.zsh`.
public enum GaiaInstallPaths {
    /// `$HOME/Library/Application Support/GaiaFTCL/bin/FranklinConsciousnessService`
    public static var franklinConsciousnessServiceBinary: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL/bin/FranklinConsciousnessService", isDirectory: false)
    }

    /// Default GRDB bundle path (same layout as `SubstrateDatabase` in GaiaFTCLCore).
    public static var substrateSQLiteURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL/substrate.sqlite", isDirectory: false)
    }

    /// JetStream store directory for `nats-server -sd` (must match install plist).
    public static var natsJetStreamStoreDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL/nats", isDirectory: true)
    }

    /// Companion overflow map for **VMAPRMAP** when inline tuples exceed the header (**Option A** overflow file).
    public static var vqbitPrimRowOverflowMapURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL/vqbit_prim_row_map.overflow", isDirectory: false)
    }

    /// Default manifold tensor backing store for **VQbitVM**.
    public static var manifoldTensorURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL/manifold.tensor", isDirectory: false)
    }

    /// Binary point log — magic **`VQBITLOG`**, **record_size = 89** (IQ gate).
    public static var vqbitPointsLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL/vqbit_points.log", isDirectory: false)
    }

    /// Binary edge log — magic **`VQEDGELG`**, **record_size = 40** (IQ gate).
    public static var vqbitEdgesLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL/vqbit_edges.log", isDirectory: false)
    }
}
