import Foundation
import GaiaFTCLCore
import Testing
import VQbitSubstrate

struct VQbitQuantumProofTests {
    @Test func iqQM006CHSHViolationsZeroSix() {
        let engine = SubstrateEngine()
        let inputs = ConstitutionalInputs(
            s1_structural: 0.9,
            s2_temporal: 0.9,
            s3_spatial: 0.9,
            s4_observable: 0.0,
            plasmaPressure: 0.9,
            fieldStrength: 0.9,
            minPlasmaPressure: 0.3,
            minFieldStrength: 0.3,
            plantKind: 0
        )
        let out = engine.checkConstitutional(inputs)
        #expect(out.violationCode == 0x06)
        #expect(out.terminalState == .refused)
    }

    @Test func p0TensorC4SourcedFromEngineNotS4Replica() {
        let engine = SubstrateEngine()
        let inputs = ConstitutionalInputs(
            s1_structural: 0.51,
            s2_temporal: 0.52,
            s3_spatial: 0.53,
            s4_observable: 0.54,
            plasmaPressure: 0.51,
            fieldStrength: 0.53,
            minPlasmaPressure: 0.3,
            minFieldStrength: 0.3,
            plantKind: 0
        )
        let out = engine.checkConstitutional(inputs)
        #expect(out.violationCode == 0)
        // C⁴ mapping per **`ConstitutionalOutputs`** (pipeline persists these to mmap **[16..31]**).
        #expect(out.c1_trust == 0.51)
        #expect(out.c2_identity == 0.52)
        #expect(out.c3_closure == 0.53)
        #expect(out.c4_consequence == 0.54)
    }

    @Test func p0ClosureResidualDomainMean() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vqtensor-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let tensorURL = tmp.appendingPathComponent("t.vqtensor")
        let overflowURL = tmp.appendingPathComponent("ovf.dat")
        let a = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!
        let store = try ManifoldTensorStore(tensorPath: tensorURL, overflowURL: overflowURL, rowCount: 4)
        let r0 = try store.row(for: a)
        let r1 = try store.row(for: b)
        for d in 0 ..< 4 { try store.writeFloat(row: r0, dimension: UInt8(d), value: 0.5) }
        for d in 0 ..< 4 { try store.writeFloat(row: r1, dimension: UInt8(d), value: 0.5) }
        let residual = try ManifoldConstitutionalClosurePhysics.computeClosureResidual(
            store: store,
            threshold: 0.8,
            domainPrimIDs: [a, b]
        )
        #expect(abs(residual - 0.375) < 1e-6)
    }
}
