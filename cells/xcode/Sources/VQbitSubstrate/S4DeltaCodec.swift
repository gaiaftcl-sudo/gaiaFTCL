import Foundation

/// **S⁴ delta** wire record — **`gaiaftcl.substrate.s4.delta`** — **34 bytes**, **`protocol_version`** **[33]** = **1**.
public struct S4DeltaWire: Equatable, Sendable {
    public static let byteCount = 34
    public static let protocolVersion: UInt8 = 1
    public static let protocolVersionOffset = 33

    public var primID: UUID
    /// Structural dimension **0…3**, or **`0xFF`** = inject **all four** **S⁴** dims at **`newValue`** (OQ single-shot wire).
    public var dimension: UInt8

    /// Broadcast token — sets **s1…s4** to **`newValue`** in one frame.
    public static let allStructuralDimensions: UInt8 = 0xFF
    public var oldValue: Float
    public var newValue: Float
    public var sequence: Int64

    public init(primID: UUID, dimension: UInt8, oldValue: Float, newValue: Float, sequence: Int64) {
        self.primID = primID
        self.dimension = dimension
        self.oldValue = oldValue
        self.newValue = newValue
        self.sequence = sequence
    }
}

public enum S4DeltaCodec {
    public static func encode(_ v: S4DeltaWire) throws -> Data {
        var d = Data()
        d.reserveCapacity(S4DeltaWire.byteCount)
        d.append(contentsOf: uuidBytes(v.primID))
        d.append(v.dimension)
        d.append(contentsOf: floatLE(v.oldValue))
        d.append(contentsOf: floatLE(v.newValue))
        d.append(contentsOf: int64LE(v.sequence))
        d.append(S4DeltaWire.protocolVersion)
        precondition(d.count == S4DeltaWire.byteCount)
        return d
    }

    public static func decode(_ data: Data) throws -> S4DeltaWire {
        guard data.count == S4DeltaWire.byteCount else {
            throw SubstrateCodecError.invalidLength(expected: S4DeltaWire.byteCount, actual: data.count)
        }
        let pv = data[S4DeltaWire.protocolVersionOffset]
        guard pv == S4DeltaWire.protocolVersion else {
            throw SubstrateCodecError.unsupportedProtocolVersion(found: pv, expected: S4DeltaWire.protocolVersion)
        }
        let prim = try uuidFromData(data, offset: 0)
        let dim = data[16]
        let oldF = floatFromLE(data, offset: 17)
        let newF = floatFromLE(data, offset: 21)
        let seq = int64FromLE(data, offset: 25)
        return S4DeltaWire(primID: prim, dimension: dim, oldValue: oldF, newValue: newF, sequence: seq)
    }
}
