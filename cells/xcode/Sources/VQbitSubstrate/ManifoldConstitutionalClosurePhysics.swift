import Accelerate
import Foundation

/// Physics-grade constitutional closure residual: **Float64** manifold means, domain **`constitutional_threshold_calorie`** from substrate, **Accelerate** mean over **N** assigned prims (**no integer approximation** of the mean beyond IEEE-754 summation in **`vDSP`**).
public enum ManifoldConstitutionalClosurePhysics {

    /// **`Σ constitutional_stress(p) / N`** with **`constitutional_stress(p) = max(0, (τ − prim_mean(p)) / τ)`**, **`prim_mean(p) = (s1+s2+s3+s4)/4`** in **Double**, reading **Float32** tensor slots and promoting immediately.
    public static func meanConstitutionalStress(
        store: ManifoldTensorStore,
        calorieThresholdForPrim: (UUID) -> Double
    ) throws -> Double {
        let pairs = store.primToRow.sorted { $0.key.uuidString < $1.key.uuidString }
        let n = pairs.count
        guard n > 0 else { return 0 }

        var stresses = ContiguousArray<Double>(repeating: 0, count: n)
        for i in 0 ..< n {
            let (prim, row) = pairs[i]
            let s1 = Double(try store.readFloat(row: row, dimension: 0))
            let s2 = Double(try store.readFloat(row: row, dimension: 1))
            let s3 = Double(try store.readFloat(row: row, dimension: 2))
            let s4 = Double(try store.readFloat(row: row, dimension: 3))
            let primMean = (s1 + s2 + s3 + s4) * 0.25
            let tau = calorieThresholdForPrim(prim)
            guard tau > 0 else {
                stresses[i] = 0
                continue
            }
            stresses[i] = max(0, (tau - primMean) / tau)
        }

        var meanStress: Double = 0
        stresses.withUnsafeBufferPointer { bp in
            vDSP_meanvD(bp.baseAddress!, 1, &meanStress, vDSP_Length(n))
        }
        return min(max(meanStress, 0), 1)
    }

    /// **`c3_closure` physics channel:** **`1 − closureResidual`**, clamped to **[0, 1]**.
    public static func c3Closure(fromMeanStress closureResidual: Double) -> Double {
        min(max(1 - closureResidual, 0), 1)
    }

    /// Domain-specific constitutional closure residual: **Float64** mean via **`vDSP_meanvD`**
    /// over **`constitutional_stress`** for prims in **`domainPrimIDs`** only (not global prim count).
    public static func computeClosureResidual(
        store: ManifoldTensorStore,
        threshold: Double,
        domainPrimIDs: [UUID]
    ) throws -> Double {
        let n = domainPrimIDs.count
        guard n > 0 else { return 0.0 }
        guard threshold > 0 else { return 0.0 }

        var stressVector = [Double](repeating: 0.0, count: n)
        for (idx, primID) in domainPrimIDs.enumerated() {
            guard let rowIndex = store.primToRow[primID] else { continue }
            let s1 = Double(try store.readFloat(row: rowIndex, dimension: 0))
            let s2 = Double(try store.readFloat(row: rowIndex, dimension: 1))
            let s3 = Double(try store.readFloat(row: rowIndex, dimension: 2))
            let s4 = Double(try store.readFloat(row: rowIndex, dimension: 3))
            let sMean = (s1 + s2 + s3 + s4) * 0.25
            stressVector[idx] = max(0.0, (threshold - sMean) / threshold)
        }
        var result = 0.0
        stressVector.withUnsafeBufferPointer { bp in
            vDSP_meanvD(bp.baseAddress!, 1, &result, vDSP_Length(n))
        }
        return min(max(result, 0.0), 1.0)
    }
}
