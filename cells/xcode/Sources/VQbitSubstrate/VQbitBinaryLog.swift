import Foundation

// MARK: - Magic bytes

public enum VQbitBinaryLogMagic {
    /// 4-byte magic for vqbit_points.log
    public static let points: UInt32 = 0x5651_4250  // "VQBP"
    /// 4-byte magic for vqbit_edges.log
    public static let edges: UInt32 = 0x5651_4245   // "VQBE"
    /// 4-byte magic for vqbit_tensor.log
    public static let tensor: UInt32 = 0x5651_4254  // "VQBT"
}

// MARK: - Header layout (32 bytes)
// [0..3]   magic UInt32 LE
// [4]      version UInt8
// [5..7]   pad
// [8..11]  recordSize UInt32 LE
// [12..27] cellID UUID (16 bytes)
// [28..31] pad

public struct VQbitBinaryLogHeader: Sendable {
    public static let byteCount = 32
    public let magic: UInt32
    public let version: UInt8
    public let recordSize: UInt32
    public let cellID: UUID
}

// MARK: - Codec

public enum VQbitBinaryLogCodec {
    public static let pointsRecordSize: UInt32 = UInt32(VQbitPointsRecordWire.byteCount)

    public static func encodeHeader(magic: UInt32, version: UInt8, recordSize: UInt32, cellID: UUID) -> Data {
        var d = Data(count: VQbitBinaryLogHeader.byteCount)
        d[0 ..< 4] = Data(uint32LE(magic))
        d[4] = version
        d[5] = 0; d[6] = 0; d[7] = 0
        d[8 ..< 12] = Data(uint32LE(recordSize))
        d[12 ..< 28] = Data(uuidBytes(cellID))
        d[28] = 0; d[29] = 0; d[30] = 0; d[31] = 0
        return d
    }

    public static func parseHeader(_ data: some DataProtocol) throws -> VQbitBinaryLogHeader {
        let bytes = Data(data)
        guard bytes.count >= VQbitBinaryLogHeader.byteCount else {
            throw SubstrateCodecError.truncatedHeader
        }
        let magic = uint32FromLE(bytes, offset: 0)
        let version = bytes[4]
        let recordSize = uint32FromLE(bytes, offset: 8)
        let cellID = try uuidFromData(bytes, offset: 12)
        return VQbitBinaryLogHeader(magic: magic, version: version, recordSize: recordSize, cellID: cellID)
    }

    public static let edgesRecordSize: UInt32 = 42

    public static func verifyPointsFileHeader(_ data: some DataProtocol) throws {
        let header = try parseHeader(data)
        guard header.magic == VQbitBinaryLogMagic.points else {
            throw SubstrateCodecError.invalidMagic
        }
    }

    public static func verifyEdgesFileHeader(_ data: some DataProtocol) throws {
        let header = try parseHeader(data)
        guard header.magic == VQbitBinaryLogMagic.edges else {
            throw SubstrateCodecError.invalidMagic
        }
    }
}
