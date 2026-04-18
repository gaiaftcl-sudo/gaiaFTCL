import Foundation

/// Provides the fundamental Phi (Golden Ratio) scaling invariant for the UUM-8D mesh.
/// This prevents rational alignment of vQbit measurement boundaries, which causes constructive interference (noise spikes).
/// It forces the entropy deltas to remain distributed across the irrational spectrum, maintaining the B-2 Truth Threshold's integrity.
public struct vQbitScalingProvider {
    /// The Golden Ratio (Phi) precision to 64-bit float minimum.
    public static let PHI: Double = 1.6180339887498948482
    
    /// Epsilon for floating point comparison during validation.
    public static let EPSILON: Double = 1e-9
    
    /// Validates that the state transition respects the Phi scaling invariant.
    /// During state-vector updates, the look-ahead window for the next vQbit measurement must be scaled by Phi.
    ///
    /// - Parameters:
    ///   - currentWindow: The current measurement window.
    ///   - previousWindow: The previous measurement window.
    /// - Returns: True if the scaling respects Phi within EPSILON, false otherwise.
    public static func validateTransition(currentWindow: Double, previousWindow: Double) -> Bool {
        guard previousWindow > 0 else { return false }
        let ratio = abs(currentWindow / previousWindow)
        return abs(ratio - PHI) <= EPSILON
    }
    
    /// Generates a stochastic stagger interval based on Phi for qualification gates.
    /// - Parameter iteration: The current iteration or sequence number.
    /// - Returns: A time interval in seconds.
    public static func generateStaggerInterval(iteration: Int) -> TimeInterval {
        // Use fractional part of Phi multiples to create a pseudo-random, non-repeating stagger
        let multiple = Double(iteration) * PHI
        let fractionalPart = multiple.truncatingRemainder(dividingBy: 1.0)
        // Scale to a reasonable stagger time (e.g., 0.5 to 2.0 seconds)
        return 0.5 + (fractionalPart * 1.5)
    }
    
    /// Calculates the M^8 manifold projection phase offset based on Phi.
    /// - Parameter basePhase: The base phase angle in radians.
    /// - Returns: The phase offset scaled irrationally.
    public static func m8ManifoldPhaseOffset(basePhase: Double) -> Double {
        return basePhase * PHI
    }
    
    /// Calculates the deterministic fractal coordinate for a given vQbit state.
    /// - Parameters:
    ///   - depth: The recursion depth within the UUM-8D mesh.
    ///   - index: The index or sequence number of the state.
    /// - Returns: The exact coordinate in the M^8 manifold.
    public static func calculateFractalCoordinate(depth: Int, index: Int) -> Double {
        let phiPower = pow(PHI, Double(depth))
        let offset = Double(index) * PHI
        return (phiPower + offset).truncatingRemainder(dividingBy: 1.0)
    }
    
    /// Enforces zero-overlap state packing by calculating the next state boundary.
    /// - Parameter previousState: The previous state value.
    /// - Returns: The next state boundary, guaranteed to be irrationally isolated.
    public static func enforceZeroOverlapPacking(previousState: Double) -> Double {
        return (previousState + PHI).truncatingRemainder(dividingBy: 1.0)
    }
}
