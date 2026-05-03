import Foundation
import VQbitSubstrate

/// In-memory terminal manifold keyed by **prim_id** — fed exclusively by **`gaiaftcl.substrate.c4.projection`** (NATS → Franklin).
public actor ManifoldProjectionStore {
    public static let shared = ManifoldProjectionStore()

    private var latest: [UUID: C4ProjectionWire] = [:]

    public func state(for primID: UUID) -> C4ProjectionWire? {
        latest[primID]
    }

    public func apply(_ wire: C4ProjectionWire) {
        latest[wire.primID] = wire
    }

    /// Qualification / wake-validation seed only — never used as fake NATS authority.
    public func seedForTests(primID: UUID, wire: C4ProjectionWire) {
        latest[primID] = wire
    }

    public func resetForTests() {
        latest.removeAll()
    }
}
