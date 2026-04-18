import Foundation

/// Protocol for mesh connectivity abstraction
/// Production implementation: LiveMeshConnector
/// Test implementation: NONE (zero mock rule - use real infrastructure with shortened timeouts)
@MainActor
protocol MeshConnector {
    /// Current mesh connectivity status
    var isConnected: Bool { get async }
    
    /// Start monitoring mesh connectivity
    func startMonitoring() async throws
    
    /// Stop monitoring mesh connectivity
    func stopMonitoring() async
    
    /// Set callback for mesh connectivity changes
    func onConnectivityChange(_ handler: @escaping (Bool) -> Void)
}
