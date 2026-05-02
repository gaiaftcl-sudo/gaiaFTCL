import Foundation
import Testing
@testable import VQbitSubstrate

struct WireCodecTests {
    @Test func s4RoundTrip() throws {
        let u = UUID(uuidString: "AABBCCDD-EEFF-0011-2233-445566778899")!
        let orig = S4DeltaWire(
            primID: u,
            dimension: 2,
            oldValue: 1.25,
            newValue: 3.5,
            sequence: 9_001
        )
        let data = try S4DeltaCodec.encode(orig)
        #expect(data.count == S4DeltaWire.byteCount)
        let back = try S4DeltaCodec.decode(data)
        #expect(back == orig)
    }

    @Test func c4RoundTrip() throws {
        let u = UUID(uuidString: "01020304-0506-0708-090a-0b0c0d0e0f10")!
        let orig = C4ProjectionWire(
            primID: u,
            c1Trust: 0.9,
            c2Identity: 1,
            c3Closure: 0.2,
            c4Consequence: 0,
            terminal: 0,
            refusalSource: 0,
            violationCode: 0,
            sequence: -42
        )
        let data = try C4ProjectionCodec.encode(orig)
        #expect(data.count == C4ProjectionWire.byteCount)
        let back = try C4ProjectionCodec.decode(data)
        #expect(back == orig)
    }

    @Test func vmaPRSelfTestClean() {
        let errs = ManifoldTensorIQSelfTest.verify()
        #expect(errs.isEmpty, "\(errs)")
    }

    @Test func vqbitPointsRecordRoundTrip() throws {
        let u = UUID(uuidString: "12345678-1234-4123-8123-123456789abc")!
        let env = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let cell = UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!
        let orig = VQbitPointsRecordWire(
            primID: u,
            s1: 0.8, s2: 0.7, s3: 0.6, s4: 0.9,
            c1: 0.55, c2: 0.66, c3: 0.77, c4: 0.88,
            terminal: 1,
            timestampMicros: 9_001,
            envelopeID: env,
            cellID: cell
        )
        let data = VQbitPointsRecordCodec.encode(orig)
        #expect(data.count == VQbitPointsRecordWire.byteCount)
        let back = try VQbitPointsRecordCodec.decode(data)
        #expect(back == orig)
    }

    @Test func binaryLogHeadersRoundTrip() throws {
        let cid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let ph = VQbitBinaryLogCodec.encodeHeader(
            magic: VQbitBinaryLogMagic.points,
            version: 1,
            recordSize: VQbitBinaryLogCodec.pointsRecordSize,
            cellID: cid
        )
        try VQbitBinaryLogCodec.verifyPointsFileHeader(ph)
        let eh = VQbitBinaryLogCodec.encodeHeader(
            magic: VQbitBinaryLogMagic.edges,
            version: 1,
            recordSize: VQbitBinaryLogCodec.edgesRecordSize,
            cellID: cid
        )
        try VQbitBinaryLogCodec.verifyEdgesFileHeader(eh)
    }
}
