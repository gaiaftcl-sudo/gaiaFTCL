import CryptoKit
import Foundation

/// Deterministic UUIDs for USD / NATS prim correlation (**Swift-only**, no `getnewaddress` entropy).
public enum GaiaFTCLPrimIdentity {
    public static func uuid(gameID: String, domain: String) -> UUID {
        let basis = "GaiaFTCL.language-game.\(domain).\(gameID)"
        let digest = SHA256.hash(data: Data(basis.utf8))
        var b = [UInt8](digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
        ))
    }

    /// Deterministic prim UUID for the sealed **`language_game_contracts`** row (**game_id** + **domain**).
    public static func primID(contractGameID: String, contractDomain: String) -> UUID {
        uuid(gameID: contractGameID, domain: contractDomain.lowercased())
    }
}
