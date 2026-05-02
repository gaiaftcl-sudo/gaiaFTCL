import Foundation

/// Neighbor hit against **`vqbit_points.log`** for digital-twin search in **M⁸**.
public struct VQbitNeighbor: Sendable {
    public let record: VQbitPointsRecordWire
    public let score: Float
}

/// Live mmap-backed reader for sovereign point logs (**no simulation** — reads bytes on disk).
public struct VQbitSubstrate: Sendable {
    public let pointLogURL: URL
    public let edgeLogURL: URL
    public let cellID: UUID

    public init(pointLogURL: URL, edgeLogURL: URL, cellID: UUID) {
        self.pointLogURL = pointLogURL
        self.edgeLogURL = edgeLogURL
        self.cellID = cellID
    }

    /// **k**-nearest in normalized **L²** over **8** active dimensions; score **`1 / (1 + dist)`**.
    public func kNearest(to query: VQbitPointsRecordWire, k: Int) async throws -> [VQbitNeighbor] {
        guard k > 0 else { return [] }
        guard FileManager.default.fileExists(atPath: pointLogURL.path) else { return [] }
        let data = try Data(contentsOf: pointLogURL, options: [.mappedIfSafe])
        guard data.count >= VQbitBinaryLogHeader.byteCount else { return [] }
        try VQbitBinaryLogCodec.verifyPointsFileHeader(data.prefix(VQbitBinaryLogHeader.byteCount))
        let header = try VQbitBinaryLogCodec.parseHeader(data.prefix(VQbitBinaryLogHeader.byteCount))
        let rs = Int(header.recordSize)
        guard rs == VQbitPointsRecordWire.byteCount else { return [] }
        var offset = VQbitBinaryLogHeader.byteCount
        var scored: [(VQbitPointsRecordWire, Double)] = []
        let q = queryFloats(query)
        while offset + rs <= data.count {
            let slice = data.subdata(in: offset ..< offset + rs)
            let rec = try VQbitPointsRecordCodec.decode(slice)
            let d = distance(q: q, rec: rec)
            scored.append((rec, d))
            offset += rs
        }
        scored.sort { $0.1 < $1.1 }
        let top = scored.prefix(k)
        return top.map { pair in
            let dist = pair.1
            let s = Float(1.0 / (1.0 + dist))
            return VQbitNeighbor(record: pair.0, score: s)
        }
    }

    private func queryFloats(_ q: VQbitPointsRecordWire) -> [Float] {
        [q.s1, q.s2, q.s3, q.s4, q.c1, q.c2, q.c3, q.c4]
    }

    private func recordFloats(_ r: VQbitPointsRecordWire) -> [Float] {
        [r.s1, r.s2, r.s3, r.s4, r.c1, r.c2, r.c3, r.c4]
    }

    private func distance(q: [Float], rec: VQbitPointsRecordWire) -> Double {
        let r = recordFloats(rec)
        var sum: Double = 0
        for i in 0 ..< min(q.count, r.count) {
            let d = Double(q[i]) - Double(r[i])
            sum += d * d
        }
        return sqrt(sum)
    }
}
