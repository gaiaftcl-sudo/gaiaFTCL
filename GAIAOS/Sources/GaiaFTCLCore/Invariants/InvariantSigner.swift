import Foundation
import CryptoKit

public struct InvariantSigner {
    public static func canonicalSerialize(_ record: InvariantRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(record)
    }
    
    public static func sign(_ record: inout InvariantRecord, walletHash: String, cellId: String) throws {
        // Create provenance block
        let provenance = Provenance(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            createdByWalletHash: walletHash,
            cellId: cellId,
            signature: ""
        )
        record.provenance = provenance
        
        let canonicalData = try canonicalSerialize(record)
        let hash = S4C4Hash.sha256(canonicalData)
        
        record.provenance?.signature = "sha256:\(hash)"
    }
    
    public static func verify(_ record: InvariantRecord) -> Bool {
        guard let sig = record.provenance?.signature else { return false }
        var tempRecord = record
        tempRecord.provenance?.signature = ""
        
        guard let canonicalData = try? canonicalSerialize(tempRecord) else { return false }
        let hash = "sha256:\(S4C4Hash.sha256(canonicalData))"
        
        return hash == sig
    }
}
