import Foundation

// MARK: — Tensor file layout (GaiaFTCL Sovereign M⁸)

/// Bytes **[0..8)** — ASCII **`VQTENSOR`**; map region opens with **`VMAPRMAP`**.
public enum TensorFileMagic {
    public static let vqtensor = Data("VQTENSOR".utf8)
    public static let vmaprmap = Data("VMAPRMAP".utf8)
}

/// Bytes **32…255** — **`VMAPRMAP`** inline table + overflow pointer (Option A).
public struct VMAPRMapHeader: Sendable, Equatable {
    public var mapVersion: UInt32
    public var entryCount: UInt32
    public var overflowPayloadBytes: UInt32
    /// Up to **10** `(prim_id, row)` pairs stored inline.
    public var entries: [(UUID, UInt32)]

    public static let inlineCapacity = 10
    public static let tupleStride = 20
    public static let regionByteCount = 224

    public static func == (lhs: VMAPRMapHeader, rhs: VMAPRMapHeader) -> Bool {
        lhs.mapVersion == rhs.mapVersion
            && lhs.entryCount == rhs.entryCount
            && lhs.overflowPayloadBytes == rhs.overflowPayloadBytes
            && lhs.entries.count == rhs.entries.count
            && zip(lhs.entries, rhs.entries).allSatisfy { z in z.0.0 == z.1.0 && z.0.1 == z.1.1 }
    }
}

public enum ManifoldTensorLayout {
    public static let headerBytes = 256
    public static let payloadBaseOffset = 256
    public static let bytesPerRow = 128
    public static let mapRegionRange = 32 ..< 256
}

public enum VMAPRMapCodec {
    /// Parse bytes **[32..256)** of the tensor file.
    public static func decode(_ header256: Data) throws -> VMAPRMapHeader {
        guard header256.count >= 256 else {
            throw SubstrateCodecError.invalidLength(expected: 256, actual: header256.count)
        }
        let region = header256.subdata(in: ManifoldTensorLayout.mapRegionRange)
        guard region.prefix(8) == TensorFileMagic.vmaprmap else {
            return VMAPRMapHeader(mapVersion: 0, entryCount: 0, overflowPayloadBytes: 0, entries: [])
        }
        let mv = u32FromLE(region, offset: 8)
        let ec = u32FromLE(region, offset: 12)
        let ob = u32FromLE(region, offset: 16)
        var pairs: [(UUID, UInt32)] = []
        let maxTuples = min(ec, UInt32(VMAPRMapHeader.inlineCapacity))
        var offset = 20
        for _ in 0 ..< Int(maxTuples) {
            guard offset + VMAPRMapHeader.tupleStride <= region.count else { break }
            let pid = try uuidFromData(region, offset: offset)
            let row = u32FromLE(region, offset: offset + 16)
            pairs.append((pid, row))
            offset += VMAPRMapHeader.tupleStride
        }
        return VMAPRMapHeader(mapVersion: mv, entryCount: ec, overflowPayloadBytes: ob, entries: pairs)
    }

    /// Encode **[32..256)** region (padding with zeros).
    public static func encode(_ header: VMAPRMapHeader) throws -> Data {
        guard header.entries.count <= VMAPRMapHeader.inlineCapacity else {
            throw ManifoldTensorError.inlineMapOverflow(count: header.entries.count)
        }
        var region = Data(count: ManifoldTensorLayout.mapRegionRange.count)
        region.replaceSubrange(0 ..< 8, with: TensorFileMagic.vmaprmap)
        region.replaceSubrange(8 ..< 12, with: u32LE(header.mapVersion))
        region.replaceSubrange(12 ..< 16, with: u32LE(header.entryCount))
        region.replaceSubrange(16 ..< 20, with: u32LE(header.overflowPayloadBytes))
        var o = 20
        for (pid, row) in header.entries {
            guard o + VMAPRMapHeader.tupleStride <= region.count else { break }
            region.replaceSubrange(o ..< o + 16, with: uuidBytes(pid))
            region.replaceSubrange(o + 16 ..< o + 20, with: u32LE(row))
            o += VMAPRMapHeader.tupleStride
        }
        return region
    }
}

public enum ManifoldTensorError: Error, Sendable {
    case inlineMapOverflow(count: Int)
    case rowOutOfBounds(UInt32)
}

/// IQ-only self-test: verify **VMAPRMAP** encode/decode round-trip (invoked from **GaiaRTMGate**).
public enum ManifoldTensorIQSelfTest {
    public static func verify() -> [String] {
        let sample = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let hdr = VMAPRMapHeader(mapVersion: 1, entryCount: 1, overflowPayloadBytes: 0, entries: [(sample, 0)])
        guard let region = try? VMAPRMapCodec.encode(hdr) else {
            return ["[IQ] VMAPRMAP encode failed"]
        }
        var prefix = Data(count: 256)
        prefix.replaceSubrange(0 ..< 8, with: TensorFileMagic.vqtensor)
        prefix.replaceSubrange(32 ..< 256, with: region)
        guard let decoded = try? VMAPRMapCodec.decode(prefix) else {
            return ["[IQ] VMAPRMAP decode failed"]
        }
        guard decoded == hdr else {
            return ["[IQ] VMAPRMAP round-trip mismatch"]
        }
        return []
    }
}

/// Mutable mmap-backed tensor row store with **prim_id → row** and inline **VMAPRMAP** header sync (**≤ 10** prims inline for this substrate build).
public final class ManifoldTensorStore: @unchecked Sendable {
    private let path: URL
    private let overflowURL: URL
    private var file: FileHandle?
    public let rowCount: UInt32
    public private(set) var primToRow: [UUID: UInt32] = [:]
    private var nextRow: UInt32 = 0

    public init(tensorPath: URL, overflowURL: URL, rowCount: UInt32) throws {
        self.path = tensorPath
        self.overflowURL = overflowURL
        self.rowCount = rowCount
        try bootstrapFileIfNeeded()
        try loadMap()
        file = try FileHandle(forUpdating: tensorPath)
    }

    deinit {
        try? file?.synchronize()
        try? file?.close()
    }

    private func bootstrapFileIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil)
            let fh = try FileHandle(forWritingTo: path)
            defer { try? fh.close() }
            var header = Data(count: ManifoldTensorLayout.headerBytes)
            header.replaceSubrange(0 ..< 8, with: TensorFileMagic.vqtensor)
            let payloadBytes = Int(rowCount) * ManifoldTensorLayout.bytesPerRow
            header.replaceSubrange(8 ..< 12, with: u32LE(1))
            header.replaceSubrange(12 ..< 16, with: u32LE(rowCount))
            header.replaceSubrange(16 ..< 20, with: u32LE(UInt32(ManifoldTensorLayout.bytesPerRow)))
            let emptyMap = VMAPRMapHeader(mapVersion: 1, entryCount: 0, overflowPayloadBytes: 0, entries: [])
            let region = try VMAPRMapCodec.encode(emptyMap)
            header.replaceSubrange(32 ..< 256, with: region)
            try fh.seek(toOffset: 0)
            try fh.write(contentsOf: header)
            try fh.seek(toOffset: UInt64(ManifoldTensorLayout.payloadBaseOffset))
            try fh.write(contentsOf: Data(count: payloadBytes))
        }
    }

    private func loadMap() throws {
        let fh = try FileHandle(forReadingFrom: path)
        defer { try? fh.close() }
        try fh.seek(toOffset: 0)
        guard let header = try fh.read(upToCount: ManifoldTensorLayout.headerBytes) else {
            throw SubstrateCodecError.invalidLength(expected: ManifoldTensorLayout.headerBytes, actual: 0)
        }
        guard header.count == ManifoldTensorLayout.headerBytes else {
            throw SubstrateCodecError.invalidLength(expected: ManifoldTensorLayout.headerBytes, actual: header.count)
        }
        let map = try VMAPRMapCodec.decode(header)
        primToRow = Dictionary(uniqueKeysWithValues: map.entries)
        nextRow = 0
        if !map.entries.isEmpty {
            nextRow = map.entries.map { $0.1 }.max()! + 1
        }
    }

    public func row(for primID: UUID) throws -> UInt32 {
        if let r = primToRow[primID] { return r }
        guard primToRow.count < VMAPRMapHeader.inlineCapacity else {
            throw ManifoldTensorError.inlineMapOverflow(count: primToRow.count + 1)
        }
        guard nextRow < rowCount else {
            throw ManifoldTensorError.rowOutOfBounds(nextRow)
        }
        let r = nextRow
        nextRow += 1
        primToRow[primID] = r
        try persistHeader()
        return r
    }

    public func hasRow(for primID: UUID) -> Bool {
        primToRow[primID] != nil
    }

    /// Read-only check for other processes (headless audit) using the on-disk **VMAPRMAP** header.
    public static func hasRow(for primID: UUID, tensorPath: URL) -> Bool {
        guard let data = try? Data(contentsOf: tensorPath, options: [.mappedIfSafe]),
              data.count >= ManifoldTensorLayout.headerBytes
        else { return false }
        let header = data.subdata(in: 0 ..< ManifoldTensorLayout.headerBytes)
        guard let map = try? VMAPRMapCodec.decode(header) else { return false }
        return map.entries.contains { $0.0 == primID }
    }

    public func writeFloat(row: UInt32, dimension: UInt8, value: Float) throws {
        guard row < rowCount, dimension < 8 else {
            throw ManifoldTensorError.rowOutOfBounds(row)
        }
        let off = UInt64(ManifoldTensorLayout.payloadBaseOffset)
            + UInt64(row) * UInt64(ManifoldTensorLayout.bytesPerRow)
            + UInt64(dimension) * 4
        guard let fh = file else { throw ManifoldTensorError.rowOutOfBounds(row) }
        try fh.seek(toOffset: off)
        try fh.write(contentsOf: floatLE(value))
        try fh.synchronize()
    }

    public func readFloat(row: UInt32, dimension: UInt8) throws -> Float {
        guard row < rowCount, dimension < 8 else {
            throw ManifoldTensorError.rowOutOfBounds(row)
        }
        let off = UInt64(ManifoldTensorLayout.payloadBaseOffset)
            + UInt64(row) * UInt64(ManifoldTensorLayout.bytesPerRow)
            + UInt64(dimension) * 4
        guard let fh = file else { throw ManifoldTensorError.rowOutOfBounds(row) }
        try fh.seek(toOffset: off)
        guard let chunk = try fh.read(upToCount: 4), chunk.count == 4 else {
            throw SubstrateCodecError.invalidLength(expected: 4, actual: 0)
        }
        return floatFromLE(chunk, offset: 0)
    }

    /// Writes all 8 M⁸ dims (s1-s4, c1-c4) in one call — tensor is source of truth before NATS/disk.
    public func writeManifoldM8Row(row: UInt32, s1: Float, s2: Float, s3: Float, s4: Float,
                                   c1: Float, c2: Float, c3: Float, c4: Float) throws {
        let dims: [Float] = [s1, s2, s3, s4, c1, c2, c3, c4]
        for (i, v) in dims.enumerated() {
            try writeFloat(row: row, dimension: UInt8(i), value: v)
        }
    }

    private func persistHeader() throws {
        let entries = primToRow.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { k in
            primToRow[k].map { (k, $0) }
        }
        let hdr = VMAPRMapHeader(
            mapVersion: 1,
            entryCount: UInt32(entries.count),
            overflowPayloadBytes: 0,
            entries: entries
        )
        let region = try VMAPRMapCodec.encode(hdr)
        var prefix = Data(count: ManifoldTensorLayout.headerBytes)
        prefix.replaceSubrange(0 ..< 8, with: TensorFileMagic.vqtensor)
        prefix.replaceSubrange(8 ..< 12, with: u32LE(1))
        prefix.replaceSubrange(12 ..< 16, with: u32LE(rowCount))
        prefix.replaceSubrange(16 ..< 20, with: u32LE(UInt32(ManifoldTensorLayout.bytesPerRow)))
        prefix.replaceSubrange(32 ..< 256, with: region)
        guard let fh = file else { return }
        try fh.seek(toOffset: 0)
        try fh.write(contentsOf: prefix)
        try fh.synchronize()
    }
}

// MARK: — Read-only tensor probe (Franklin domain improvement / audit)

/// Headless read path for **S⁴** floats **without** opening a writable **`ManifoldTensorStore`**.
public enum ManifoldTensorProbe {
    public static func readRowCount(tensorPath: URL) throws -> UInt32 {
        let fh = try FileHandle(forReadingFrom: tensorPath)
        defer { try? fh.close() }
        guard let head = try fh.read(upToCount: ManifoldTensorLayout.headerBytes),
              head.count == ManifoldTensorLayout.headerBytes
        else {
            throw SubstrateCodecError.invalidLength(expected: ManifoldTensorLayout.headerBytes, actual: 0)
        }
        return u32FromLE(head, offset: 12)
    }

    /// Returns **(s1,s2,s3,s4)** tensor slice for **`primID`**, or **`nil`** if missing / unreadable.
    public static func readMeanS4(primID: UUID, tensorPath: URL) throws -> (Float, Float, Float, Float)? {
        guard FileManager.default.fileExists(atPath: tensorPath.path) else { return nil }
        let fh = try FileHandle(forReadingFrom: tensorPath)
        defer { try? fh.close() }
        guard let head = try fh.read(upToCount: ManifoldTensorLayout.headerBytes),
              head.count == ManifoldTensorLayout.headerBytes
        else { return nil }
        let map = try VMAPRMapCodec.decode(head)
        guard let row = map.entries.first(where: { $0.0 == primID })?.1 else { return nil }
        let rowCount = u32FromLE(head, offset: 12)
        guard row < rowCount else { return nil }
        let base = UInt64(ManifoldTensorLayout.payloadBaseOffset)
            + UInt64(row) * UInt64(ManifoldTensorLayout.bytesPerRow)
        var vals: [Float] = []
        for dim in 0 ..< 4 {
            try fh.seek(toOffset: base + UInt64(dim) * 4)
            guard let chunk = try fh.read(upToCount: 4), chunk.count == 4 else { return nil }
            vals.append(floatFromLE(chunk, offset: 0))
        }
        return (vals[0], vals[1], vals[2], vals[3])
    }

    /// Weakest **S⁴** dimension index **0…3** (lowest tensor component). Defaults to **0** if unreadable.
    public static func weakestS4Dimension(primID: UUID, tensorPath: URL) -> Int {
        guard let tuple = try? readMeanS4(primID: primID, tensorPath: tensorPath) else { return 0 }
        let vals = [tuple.0, tuple.1, tuple.2, tuple.3]
        var best = 0
        var bestV = vals[0]
        for i in 1 ..< 4 where vals[i] < bestV {
            bestV = vals[i]
            best = i
        }
        return best
    }
}
