import Foundation

// Metal GNN dispatch — no-op stub for non-GPU builds.
enum VQbitMetalHarness {
    static func dispatchIdleTick() {}
}
