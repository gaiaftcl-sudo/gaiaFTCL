import Foundation

// MARK: - UUID

func uuidBytes(_ uuid: UUID) -> [UInt8] {
    let t = uuid.uuid
    return [
        t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
        t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15
    ]
}

func uuidFromData(_ data: Data, offset: Int) throws -> UUID {
    guard data.count >= offset + 16 else {
        throw SubstrateCodecError.malformedUUID(offset: offset)
    }
    let b = Array(data[offset ..< offset + 16])
    let t = (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
             b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    return UUID(uuid: t)
}

// MARK: - Float32 little-endian

func floatLE(_ v: Float) -> [UInt8] {
    var bits = v.bitPattern.littleEndian
    return withUnsafeBytes(of: &bits) { Array($0) }
}

func floatFromLE(_ data: Data, offset: Int) -> Float {
    var bits: UInt32 = 0
    _ = withUnsafeMutableBytes(of: &bits) { ptr in
        data.copyBytes(to: ptr, from: offset ..< offset + 4)
    }
    return Float(bitPattern: UInt32(littleEndian: bits))
}

// MARK: - Int64 little-endian

func int64LE(_ v: Int64) -> [UInt8] {
    var le = v.littleEndian
    return withUnsafeBytes(of: &le) { Array($0) }
}

func int64FromLE(_ data: Data, offset: Int) -> Int64 {
    var raw: Int64 = 0
    _ = withUnsafeMutableBytes(of: &raw) { ptr in
        data.copyBytes(to: ptr, from: offset ..< offset + 8)
    }
    return Int64(littleEndian: raw)
}

// MARK: - UInt32 little-endian (u32LE / u32FromLE aliases used by ManifoldTensorAllocator)

@inline(__always) func u32LE(_ v: UInt32) -> [UInt8] { uint32LE(v) }
@inline(__always) func u32FromLE(_ data: Data, offset: Int) -> UInt32 { uint32FromLE(data, offset: offset) }

func uint32LE(_ v: UInt32) -> [UInt8] {
    var le = v.littleEndian
    return withUnsafeBytes(of: &le) { Array($0) }
}

func uint32FromLE(_ data: Data, offset: Int) -> UInt32 {
    var raw: UInt32 = 0
    _ = withUnsafeMutableBytes(of: &raw) { ptr in
        data.copyBytes(to: ptr, from: offset ..< offset + 4)
    }
    return UInt32(littleEndian: raw)
}
