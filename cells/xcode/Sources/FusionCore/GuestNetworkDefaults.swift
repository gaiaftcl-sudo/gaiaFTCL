import Foundation

/// Canonical network constants for the GaiaOS guest substrate (VM / mesh relay topology).
public enum GuestNetworkDefaults {
    /// The sovereign Gaia mesh — Hetzner Helsinki head node, wallet_gate relay.
    /// Mac cell connects OUT to this; do not use 127.0.0.1 for mesh.
    public static let natsMeshHost: String   = "gaiaftcl.com"
    public static let natsRelayPort: UInt16  = 8803
    public static let natsGuestPort: UInt16  = 4222
    /// Localhost bind address — used only for services that listen locally (MCP).
    public static let listenHost: String     = "127.0.0.1"
    public static let virtioFsTag: String    = "gaiaos"
    public static let defaultGuestIpv4: String = "192.168.64.10"
    /// Franklin MCP server — JSON-RPC 2.0 on localhost for Xcode ↔ Franklin comms.
    public static let franklinMCPPort: UInt16 = 8831

    /// All 9 sovereign mesh cell endpoints — tried in round-robin order on connection failure.
    /// wallet_gate (port 8803) is the NATS relay on every cell.
    public static let natsMeshEndpoints: [(host: String, port: UInt16)] = [
        ("gaiaftcl.com",      8803),  // DNS round-robin / head node
        ("77.42.85.60",       8803),  // HEL1-01 (Hetzner Helsinki)
        ("37.120.187.247",    8803),  // HEL1-02
        ("37.120.187.174",    8803),  // HEL1-03
        ("37.27.7.9",         8803),  // HEL1-04
        ("77.42.32.156",      8803),  // HEL1-05
        ("77.42.88.110",      8803),  // NUE1-01 (Netcup Nuremberg)
        ("135.181.88.134",    8803),  // NUE1-02
        ("152.53.88.141",     8803),  // NUE1-03
        ("152.53.91.220",     8803),  // NUE1-04
    ]
}
