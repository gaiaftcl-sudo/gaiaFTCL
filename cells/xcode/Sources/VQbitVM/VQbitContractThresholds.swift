import Foundation

/// Cached **`constitutional_threshold_calorie`** map (**prim UUID → τ**) loaded from **`language_game_contracts`** once before the NATS loop — **Double** throughout.
final class VQbitContractThresholds: @unchecked Sendable {
    static let shared = VQbitContractThresholds()

    private let lock = NSLock()
    private var primToCalorie: [UUID: Double] = [:]

    func replace(with map: [UUID: Double]) {
        lock.lock()
        primToCalorie = map
        lock.unlock()
    }

    /// Threshold τ for constitutional stress; unknown prim falls back to any active row’s τ, then **1.0** if the cache is empty.
    func calorie(for primID: UUID) -> Double {
        lock.lock()
        let map = primToCalorie
        lock.unlock()
        if let t = map[primID] { return t }
        if let first = map.values.first { return first }
        return 1
    }

    private init() {}
}
