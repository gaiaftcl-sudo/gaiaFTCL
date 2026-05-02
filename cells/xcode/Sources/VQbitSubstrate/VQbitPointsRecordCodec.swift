import Foundation

/// Single row in **`vqbit_points.log`** — **89 bytes** — UUM-8D anchor (**S⁴ × C⁴**).
public struct VQbitPointsRecordWire: Equatable, Sendable {
    public static let byteCount = 89

    public var primID: UUID
    public var s1: Float
    public var s2: Float
    public var s3: Float
    public var s4: Float
    public var c1: Float
    public var c2: Float
    public var c3: Float
    public var c4: Float
    public var terminal: UInt8
    public var timestampMicros: Int64
    public var envelopeID: UUID
    public var cellID: UUID

    public init(
        primID: UUID,
        s1: Float,
        s2: Float,
        s3: Float,
        s4: Float,
        c1: Float,
        c2: Float,
        c3: Float,
        c4: Float,
        terminal: UInt8,
        timestampMicros: Int64,
        envelopeID: UUID,
        cellID: UUID
    ) {
        self.primID = primID
        self.s1 = s1
        self.s2 = s2
        self.s3 = s3
        self.s4 = s4
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
        self.c4 = c4
        self.terminal = terminal
        self.timestampMicros = timestampMicros
        self.envelopeID = envelopeID
        self.cellID = cellID
    }
}

public enum VQbitPointsRecordCodec {
    public static func encode(_ v: VQbitPointsRecordWire) -> Data {
        var d = Data()
        d.reserveCapacity(VQbitPointsRecordWire.byteCount)
        d.append(contentsOf: uuidBytes(v.primID))
        d.append(contentsOf: floatLE(v.s1))
        d.append(contentsOf: floatLE(v.s2))
        d.append(contentsOf: floatLE(v.s3))
        d.append(contentsOf: floatLE(v.s4))
        d.append(contentsOf: floatLE(v.c1))
        d.append(contentsOf: floatLE(v.c2))
        d.append(contentsOf: floatLE(v.c3))
        d.append(contentsOf: floatLE(v.c4))
        d.append(v.terminal)
        d.append(contentsOf: int64LE(v.timestampMicros))
        d.append(contentsOf: uuidBytes(v.envelopeID))
        d.append(contentsOf: uuidBytes(v.cellID))
        precondition(d.count == VQbitPointsRecordWire.byteCount)
        return d
    }

    public static func decode(_ data: Data) throws -> VQbitPointsRecordWire {
        guard data.count == VQbitPointsRecordWire.byteCount else {
            throw SubstrateCodecError.invalidLength(expected: VQbitPointsRecordWire.byteCount, actual: data.count)
        }
        let prim = try uuidFromData(data, offset: 0)
        let s1 = floatFromLE(data, offset: 16)
        let s2 = floatFromLE(data, offset: 20)
        let s3 = floatFromLE(data, offset: 24)
        let s4 = floatFromLE(data, offset: 28)
        let c1 = floatFromLE(data, offset: 32)
        let c2 = floatFromLE(data, offset: 36)
        let c3 = floatFromLE(data, offset: 40)
        let c4 = floatFromLE(data, offset: 44)
        let term = data[48]
        let ts = int64FromLE(data, offset: 49)
        let env = try uuidFromData(data, offset: 57)
        let cell = try uuidFromData(data, offset: 73)
        return VQbitPointsRecordWire(
            primID: prim,
            s1: s1, s2: s2, s3: s3, s4: s4,
            c1: c1, c2: c2, c3: c3, c4: c4,
            terminal: term,
            timestampMicros: ts,
            envelopeID: env,
            cellID: cell
        )
    }
}
