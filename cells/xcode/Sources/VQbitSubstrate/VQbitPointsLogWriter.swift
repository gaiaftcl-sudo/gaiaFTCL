import Foundation

/// Appends frozen **89-byte** point records to **`vqbit_points.log`** (creates **32-byte** header if absent).
public enum VQbitPointsLogWriter {
    public static func append(record: Data, logURL: URL, cellID: UUID) throws {
        guard record.count == Int(VQbitBinaryLogCodec.pointsRecordSize) else {
            throw SubstrateCodecError.invalidLength(expected: Int(VQbitBinaryLogCodec.pointsRecordSize), actual: record.count)
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil)
            let header = VQbitBinaryLogCodec.encodeHeader(
                magic: VQbitBinaryLogMagic.points,
                version: 1,
                recordSize: VQbitBinaryLogCodec.pointsRecordSize,
                cellID: cellID
            )
            try header.write(to: logURL, options: .atomic)
        }
        let fh = try FileHandle(forWritingTo: logURL)
        defer { try? fh.close() }
        try fh.seekToEnd()
        try fh.write(contentsOf: record)
        try fh.synchronize()
    }
}
