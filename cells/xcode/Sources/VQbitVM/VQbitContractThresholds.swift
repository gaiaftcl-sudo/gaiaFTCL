import Foundation

/// Cached **`constitutional_threshold_calorie`** (**prim UUID → τ**) and **domain closure peer lists**
/// loaded from **`language_game_contracts`** once before the NATS loop — **Double** throughout.
final class VQbitContractThresholds: @unchecked Sendable {
    static let shared = VQbitContractThresholds()

    private let lock = NSLock()
    private var primToCalorie: [UUID: Double] = [:]
    /// All prim UUIDs that share the same **`domain`** column (including **`prim`** itself).
    private var peersByPrim: [UUID: [UUID]] = [:]
    private var knownPrimIDs: Set<UUID> = []

    func replace(thresholds: [UUID: Double], peersByPrim: [UUID: [UUID]]) {
        lock.lock()
        primToCalorie = thresholds
        self.peersByPrim = peersByPrim
        knownPrimIDs = Set(thresholds.keys)
        lock.unlock()
    }

    func knowsPrim(_ primID: UUID) -> Bool {
        lock.lock()
        let k = knownPrimIDs.contains(primID)
        lock.unlock()
        return k
    }

    /// Threshold τ for constitutional stress — **no silent default** when the prim is unknown to substrate contracts.
    func calorie(for primID: UUID) -> Double? {
        lock.lock()
        let v = primToCalorie[primID]
        lock.unlock()
        return v
    }

    func closurePeers(for primID: UUID) -> [UUID] {
        lock.lock()
        let list = peersByPrim[primID]
        lock.unlock()
        return list ?? []
    }

    private init() {}
}
