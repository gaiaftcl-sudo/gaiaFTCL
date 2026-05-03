import Foundation

/// **C⁴ projection** wire record — **`gaiaftcl.substrate.c4.projection`** — **53 bytes**.
public struct C4ProjectionWire: Equatable, Sendable {
    public static let byteCount = 53
    public static let protocolVersion: UInt8 = 1

    public enum Terminal: UInt8, Sendable {
        case calorie  = 0x01
        case cure     = 0x02
        case refused  = 0x03
        case blocked  = 0x04
    }

    public enum RefusalSource: UInt8, Sendable {
        case none       = 0x00
        case trust      = 0x01
        case identity   = 0x02
        case geometry   = 0x03
        case unmoored   = 0x04
        case tauStale   = 0x05
    }

    public enum ViolationCode: UInt8, Sendable {
        case none             = 0x00
        case bondDim          = 0x01
        case coherence        = 0x02
        case tensorCapacity   = 0x03
        case structural       = 0x04
        case upstreamDown     = 0x05
        case chsh             = 0x06
        case quotaExhausted   = 0x07
    }

    public var primID: UUID
    public var c1Trust: Float
    public var c2Identity: Float
    public var c3Closure: Float
    public var c4Consequence: Float
    public var terminal: Terminal
    public var refusalSource: RefusalSource
    public var violationCode: ViolationCode
    public var sequence: Int64
    public var timestampMs: Int64

    public init(
        primID: UUID,
        c1Trust: Float,
        c2Identity: Float,
        c3Closure: Float,
        c4Consequence: Float,
        terminal: Terminal,
        refusalSource: RefusalSource = .none,
        violationCode: ViolationCode = .none,
        sequence: Int64,
        timestampMs: Int64 = 0
    ) {
        self.primID = primID
        self.c1Trust = c1Trust
        self.c2Identity = c2Identity
        self.c3Closure = c3Closure
        self.c4Consequence = c4Consequence
        self.terminal = terminal
        self.refusalSource = refusalSource
        self.violationCode = violationCode
        self.sequence = sequence
        self.timestampMs = timestampMs
    }

    /// UInt8 convenience init — backward-compat with raw-byte callers and test fixtures.
    public init(
        primID: UUID,
        c1Trust: Float,
        c2Identity: Float,
        c3Closure: Float,
        c4Consequence: Float,
        terminal: UInt8,
        refusalSource: UInt8 = 0,
        violationCode: UInt8 = 0,
        sequence: Int64,
        timestampMs: Int64 = 0
    ) {
        self.primID = primID
        self.c1Trust = c1Trust
        self.c2Identity = c2Identity
        self.c3Closure = c3Closure
        self.c4Consequence = c4Consequence
        self.terminal = Terminal(rawValue: terminal) ?? .blocked
        self.refusalSource = RefusalSource(rawValue: refusalSource) ?? .none
        self.violationCode = ViolationCode(rawValue: violationCode) ?? .none
        self.sequence = sequence
        self.timestampMs = timestampMs
    }
}

public enum C4ProjectionCodec {
    // Layout:
    // [0..15]  primID UUID
    // [16..19] c1Trust Float32 LE
    // [20..23] c2Identity Float32 LE
    // [24..27] c3Closure Float32 LE
    // [28..31] c4Consequence Float32 LE
    // [32]     terminal UInt8
    // [33]     refusalSource UInt8
    // [34]     violationCode UInt8
    // [35]     protocolVersion UInt8 = 0x01
    // [36..43] sequence Int64 LE
    // [44..51] timestampMs Int64 LE
    // [52]     pad 0x00
    // Total: 53 bytes

    public static func encode(_ p: C4ProjectionWire) -> Data {
        var d = Data()
        d.reserveCapacity(C4ProjectionWire.byteCount)
        d.append(contentsOf: uuidBytes(p.primID))
        d.append(contentsOf: floatLE(p.c1Trust))
        d.append(contentsOf: floatLE(p.c2Identity))
        d.append(contentsOf: floatLE(p.c3Closure))
        d.append(contentsOf: floatLE(p.c4Consequence))
        d.append(p.terminal.rawValue)
        d.append(p.refusalSource.rawValue)
        d.append(p.violationCode.rawValue)
        d.append(C4ProjectionWire.protocolVersion)
        d.append(contentsOf: int64LE(p.sequence))
        d.append(contentsOf: int64LE(p.timestampMs))
        d.append(0x00)
        precondition(d.count == C4ProjectionWire.byteCount)
        return d
    }

    public static func decode(_ data: Data) throws -> C4ProjectionWire {
        guard data.count == C4ProjectionWire.byteCount else {
            throw SubstrateCodecError.invalidLength(expected: C4ProjectionWire.byteCount, actual: data.count)
        }
        let pv = data[35]
        guard pv == C4ProjectionWire.protocolVersion else {
            throw SubstrateCodecError.unsupportedProtocolVersion(found: pv, expected: C4ProjectionWire.protocolVersion)
        }
        let primID      = try uuidFromData(data, offset: 0)
        let c1          = floatFromLE(data, offset: 16)
        let c2          = floatFromLE(data, offset: 20)
        let c3          = floatFromLE(data, offset: 24)
        let c4          = floatFromLE(data, offset: 28)
        let term        = C4ProjectionWire.Terminal(rawValue: data[32]) ?? .blocked
        let refusal     = C4ProjectionWire.RefusalSource(rawValue: data[33]) ?? .none
        let violation   = C4ProjectionWire.ViolationCode(rawValue: data[34]) ?? .none
        let sequence    = int64FromLE(data, offset: 36)
        let timestampMs = int64FromLE(data, offset: 44)
        return C4ProjectionWire(
            primID: primID,
            c1Trust: c1, c2Identity: c2, c3Closure: c3, c4Consequence: c4,
            terminal: term, refusalSource: refusal, violationCode: violation,
            sequence: sequence, timestampMs: timestampMs
        )
    }
}
