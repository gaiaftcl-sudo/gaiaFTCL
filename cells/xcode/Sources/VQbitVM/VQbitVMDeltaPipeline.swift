import Foundation
import FusionCore
import GaiaFTCLCore
import VQbitSubstrate

/// Accumulates **S⁴** deltas per prim until all four dimensions are present, then runs **constitutional → C⁴ → log**.
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
        guard delta.dimension < 4 else { return }
        let row = try store.row(for: delta.primID)
        try store.writeFloat(row: row, dimension: delta.dimension, value: delta.newValue)

        lock.lock()
        let prim = delta.primID
        var m = mask[prim] ?? 0
        m |= 1 << delta.dimension
        mask[prim] = m
        let complete = m == 0x0F
        lock.unlock()

        guard complete else { return }

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
        let refusal: UInt8 = out.violationCode != 0 ? 0x04 : 0x00
        let term = TerminalWireBridge.visualCode(for: out.terminalState)

        let c1 = Float(out.c1_trust)
        let c2 = Float(out.c2_identity)
        let c3 = Float(out.c3_closure)
        let c4 = Float(out.c4_consequence)

        try store.writeFloat(row: row, dimension: 4, value: c1)
        try store.writeFloat(row: row, dimension: 5, value: c2)
        try store.writeFloat(row: row, dimension: 6, value: c3)
        try store.writeFloat(row: row, dimension: 7, value: c4)

        lock.lock()
        mask[prim] = 0
        lock.unlock()

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
    }
}
