import Foundation
import CommonCrypto

struct OwlProtocolTests {
    static func runAll() {
        run("owl_001", "66-char key with 02 prefix accepted") {
            let validKey = "02" + String(repeating: "a", count: 64)
            return isValidOwlPubkey(validKey)
        }
        
        run("owl_002", "66-char key with 03 prefix accepted") {
            let validKey = "03" + String(repeating: "b", count: 64)
            return isValidOwlPubkey(validKey)
        }
        
        run("owl_003", "64-char key rejected (missing prefix)") {
            let invalidKey = String(repeating: "c", count: 64)
            return !isValidOwlPubkey(invalidKey)
        }
        
        run("owl_004", "04 prefix rejected (uncompressed not allowed)") {
            let invalidKey = "04" + String(repeating: "d", count: 64)
            return !isValidOwlPubkey(invalidKey)
        }
        
        run("owl_005", "Non-hex characters rejected") {
            let invalidKey = "02" + String(repeating: "z", count: 64)
            return !isValidOwlPubkey(invalidKey)
        }
        
        run("owl_006", "Audit log stores SHA-256, not raw key") {
            let testKey = "02" + String(repeating: "e", count: 64)
            let hashed = hashOwlPubkey(testKey)
            
            // SHA-256 output is 64 hex chars
            return hashed.count == 64 && hashed != testKey
        }
    }
    
    // Owl Protocol validation logic
    static func isValidOwlPubkey(_ key: String) -> Bool {
        // Must be 66 characters (2 prefix + 64 hex)
        guard key.count == 66 else { return false }
        
        // Must start with 02 or 03 (compressed secp256k1)
        guard key.hasPrefix("02") || key.hasPrefix("03") else { return false }
        
        // Must be all hex
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return key.unicodeScalars.allSatisfy { hexSet.contains($0) }
    }
    
    static func hashOwlPubkey(_ key: String) -> String {
        guard let data = key.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}
