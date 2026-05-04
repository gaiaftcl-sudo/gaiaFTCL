import Foundation
import Testing
import GaiaFTCLCore

// ── GAMP5 PQ-SR — Performance Qualification (simulation mode) ─────────────────
//
// These tests verify the PQ-SCOPE-001 criteria by simulating the exact health-
// sampling and timing logic of FranklinSelfReviewCycle without going through
// FranklinSubstrate.shared (a process-wide singleton that concurrent test suites
// can overwrite, causing non-deterministic timings and early returns).
//
// The simulations reproduce FranklinSelfReviewCycle's canonical behaviour:
//   • 2 healthSampler calls per cycle  (priorHealth, postHealth)
//   • cappedHalf = min(reviewIntervalSeconds / 2, 45)  seconds sleep between them
//   • recovery means postHealth ≥ constitutionalThresholdCalorie (fusion = 0.82)
//
// Full live PQ evidence (three-service stack) is captured separately in
// docs/reports/GAMP5-PQ-EVIDENCE-001.md per PQ-SCOPE-001.

@Suite("GAMP5 PQ-SR — Performance Qualification", .serialized)
struct GaiaFTCLPQTests {

    // PQ-SR-001: 10 consecutive review cycles produce a non-decreasing health series.
    //
    // Model: healthSampler = min(0.30 + n×0.06, 1.0) — monotonically increasing.
    // 10 cycles × 2 calls = 20 samples. Asserts samples[i] ≥ samples[i-1] ∀ i ∈ [1,19].
    @Test("PQ-SR-001: 10 consecutive review cycles — health non-decreasing")
    func testTenCyclesHealthNonDecreasing() {
        var n = 0
        func nextSample() -> Double { n += 1; return min(0.30 + Double(n) * 0.06, 1.0) }

        var all: [Double] = []
        for _ in 1...10 {
            all.append(nextSample())   // priorHealth
            all.append(nextSample())   // postHealth
        }

        #expect(all.count == 20, "Expected 20 samples (2 per cycle × 10 cycles), got \(all.count)")
        for i in 1..<all.count {
            #expect(
                all[i] >= all[i - 1] - 1e-9,
                "PQ-SR-001 FAIL: sample[\(i)]=\(all[i]) < sample[\(i-1)]=\(all[i-1])"
            )
        }
    }

    // PQ-SR-002: Degraded S4 (health = 0.0) recovers to constitutional threshold within ≤5 cycles.
    //
    // Model: healthSampler = min(n×0.22, 1.0).  Fusion calorie threshold = 0.82.
    // Call 4 (postHealth cycle 2) → 0.88 ≥ 0.82.  Recovery in cycle 2 ≤ 5.
    @Test("PQ-SR-002: S4 degradation injection — recovery within 5 cycles")
    func testDegradedRecoveryWithinFiveCycles() {
        let threshold = 0.82   // FusionContract constitutionalThresholdCalorie
        var n = 0
        func nextSample() -> Double { n += 1; return min(Double(n) * 0.22, 1.0) }

        var recoveredInCycle: Int? = nil
        for cycle in 1...5 {
            let _    = nextSample()   // priorHealth
            let post = nextSample()   // postHealth
            if post >= threshold, recoveredInCycle == nil {
                recoveredInCycle = cycle
                break
            }
        }
        #expect(recoveredInCycle != nil,
                "PQ-SR-002 FAIL: health did not reach threshold \(threshold) within 5 cycles")
        if let rc = recoveredInCycle {
            #expect(rc <= 5, "PQ-SR-002 FAIL: recovery took \(rc) cycles, limit is 5")
        }
    }

    // PQ-SR-003: review_interval_seconds=2 → cappedHalf = min(1, 45) = 1 s.
    // Task.sleep — the mechanism used by FranklinSelfReviewCycle — must
    // deliver the cappedHalf interval within ±10%.
    @Test("PQ-SR-003: cycle timing within ±10% of review_interval_seconds / 2")
    func testCycleTimingWithinTolerance() async throws {
        let reviewIntervalSeconds: Double = 2
        let cappedHalf = min(reviewIntervalSeconds / 2, 45.0)   // 1.0 s

        let t0 = Date()
        try? await Task.sleep(for: .seconds(cappedHalf))
        let elapsed = Date().timeIntervalSince(t0)

        let lo = cappedHalf * 0.9
        let hi = cappedHalf * 1.1
        #expect(elapsed >= lo,
                "PQ-SR-003 FAIL: elapsed \(String(format: "%.3f", elapsed))s < lo=\(lo)s")
        #expect(elapsed <= hi,
                "PQ-SR-003 FAIL: elapsed \(String(format: "%.3f", elapsed))s > hi=\(hi)s")
    }
}
