import Foundation

// Global authority bridge — C4 projections from NATS update this store.
// NSLock protects mutable state; callers from any actor/thread are safe.
public enum C4ManifoldRuntimeBridge {

    private nonisolated(unsafe) static let lock = NSLock()
    private nonisolated(unsafe) static var _primManifolds:      [UUID: ManifoldState] = [:]
    private nonisolated(unsafe) static var _latestManifold:     ManifoldState = .resting
    private nonisolated(unsafe) static var _natsAuthorityUntil: Date = .distantPast

    public static var primManifolds: [UUID: ManifoldState] {
        lock.withLock { _primManifolds }
    }

    public static var latestManifold: ManifoldState {
        get { lock.withLock { _latestManifold } }
        set { lock.withLock { _latestManifold = newValue } }
    }

    public static var natsAuthorityUntil: Date {
        lock.withLock { _natsAuthorityUntil }
    }

    public static func update(primID: UUID, state: ManifoldState) {
        lock.withLock {
            _primManifolds[primID]  = state
            _latestManifold         = state
            _natsAuthorityUntil     = Date(timeIntervalSinceNow: 30)
        }
    }
}
