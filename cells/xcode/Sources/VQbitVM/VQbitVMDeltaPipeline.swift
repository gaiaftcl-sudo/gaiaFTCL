import Foundation
import FusionCore
import GaiaFTCLCore
import VQbitSubstrate

/// Accumulates **S⁴** deltas per prim until all four dimensions are present, then runs **constitutional → C⁴ → wire**.
///
/// **Unified memory contract:** the mmap row holds **8 active dims** `[s1,s2,s3,s4,c1,c2,c3,c4]` before any NATS or binary-log emission so Metal’s **GNN** always reads a full **M⁸ = S⁴ × C⁴** slice, not zeros in `[4..7]`.
final class VQbitVMDeltaPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var mask: [UUID: UInt8] = [:]

    func process(
        delta: S4DeltaWire,
        store: ManifoldTensorStore,
        engine: SubstrateEngine,
        nats: NATSClient,
        cellID: UUID,
        pointsLogURL: URL
    ) throws {
        let row = try store.row(for: delta.primID)
        let prim = delta.primID

        if delta.dimension == S4DeltaWire.allStructuralDimensions {
            for d in 0 ..< 4 {
                try store.writeFloat(row: row, dimension: UInt8(d), value: delta.newValue)
            }
            lock.lock()
            mask[prim] = 0x0F
            lock.unlock()
        } else {
            guard delta.dimension < 4 else { return }
            try store.writeFloat(row: row, dimension: delta.dimension, value: delta.newValue)

            lock.lock()
            var m = mask[prim] ?? 0
            m |= 1 << delta.dimension
            mask[prim] = m
            let complete = m == 0x0F
            lock.unlock()

            guard complete else { return }
        }

        let s1 = try store.readFloat(row: row, dimension: 0)
        let s2 = try store.readFloat(row: row, dimension: 1)
        let s3 = try store.readFloat(row: row, dimension: 2)
        let s4 = try store.readFloat(row: row, dimension: 3)

        let inputs = ConstitutionalInputs(
            s1_structural: Double(s1),
            s2_temporal: Double(s2),
            s3_spatial: Double(s3),
            s4_observable: Double(s4),
            plasmaPressure: Double(s1),
            fieldStrength: Double(s3),
            minPlasmaPressure: 0.3,
            minFieldStrength: 0.3,
            plantKind: 0
        )
        let out = engine.checkConstitutional(inputs)
        let refusal: UInt8 = out.violationCode
        let term = TerminalWireBridge.visualCode(for: out.terminalState)

        if VQbitContractThresholds.shared.knowsPrim(prim),
           let tau = VQbitContractThresholds.shared.calorie(for: prim)
        {
            let peerList = VQbitContractThresholds.shared.closurePeers(for: prim)
            if !peerList.isEmpty {
                _ = try ManifoldConstitutionalClosurePhysics.computeClosureResidual(
                    store: store,
                    threshold: tau,
                    domainPrimIDs: peerList
                )
            }
        } else {
            let msg =
                "VQbitVMDeltaPipeline: no active language_game_contract for prim \(prim); skipping domain closureResidual\n"
            FileHandle.standardError.write(Data(msg.utf8))
        }

        /// **M⁸ tensor `[16..31]`** — **C⁴** comes **only** from **`checkConstitutional`** outputs (no S⁴ echo, no global mean substituted for **c3**).
        let c1 = Float(out.c1_trust)
        let c2 = Float(out.c2_identity)
        let c3 = Float(out.c3_closure)
        let c4 = Float(out.c4_consequence)

        /// **Tensor is source of truth** — persist **S⁴ × C⁴** into bytes **`[0..31]`** (`Float32` × 8) before NATS or disk.
        try store.writeManifoldM8Row(
            row: row,
            s1: Float(inputs.s1_structural),
            s2: Float(inputs.s2_temporal),
            s3: Float(inputs.s3_spatial),
            s4: Float(inputs.s4_observable),
            c1: c1,
            c2: c2,
            c3: c3,
            c4: c4
        )

        lock.lock()
        mask[prim] = 0
        lock.unlock()

        let projection = C4ProjectionWire(
            primID: prim,
            c1Trust: c1,
            c2Identity: c2,
            c3Closure: c3,
            c4Consequence: c4,
            terminal: term,
            refusalSource: refusal,
            violationCode: out.violationCode,
            sequence: delta.sequence
        )
        let wire = try C4ProjectionCodec.encode(projection)
        nats.publish(subject: SubstrateWireSubjects.c4Projection, payload: wire)

        let ts = Int64(Date().timeIntervalSince1970 * 1_000_000)
        let record = VQbitPointsRecordWire(
            primID: prim,
            s1: s1,
            s2: s2,
            s3: s3,
            s4: s4,
            c1: c1,
            c2: c2,
            c3: c3,
            c4: c4,
            terminal: term,
            timestampMicros: ts,
            envelopeID: UUID(),
            cellID: cellID
        )
        let blob = VQbitPointsRecordCodec.encode(record)
        try VQbitPointsLogWriter.append(record: blob, logURL: pointsLogURL, cellID: cellID)
    }
}
