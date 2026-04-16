import Foundation
import Dispatch
import CommonCrypto

// ANSI colors
let RED   = "\u{001B}[0;31m"
let GRN   = "\u{001B}[0;32m"
let YEL   = "\u{001B}[1;33m"
let CYN   = "\u{001B}[0;36m"
let BOLD  = "\u{001B}[1m"
let NC    = "\u{001B}[0m"

struct TestResult {
    let id: String
    let name: String
    let passed: Bool
}

var results: [TestResult] = []

func run(_ id: String, _ name: String, _ test: () throws -> Bool) {
    let passed: Bool
    do {
        passed = try test()
    } catch {
        print("  \(RED)❌ FAIL\(NC)  [\(id)] \(name) — \(error)")
        results.append(TestResult(id: id, name: name, passed: false))
        return
    }
    
    if passed {
        print("  \(GRN)✅ PASS\(NC)  [\(id)] \(name)")
        results.append(TestResult(id: id, name: name, passed: true))
    } else {
        print("  \(RED)❌ FAIL\(NC)  [\(id)] \(name)")
        results.append(TestResult(id: id, name: name, passed: false))
    }
}

// Async test helper
func run(_ id: String, _ name: String, _ test: () async throws -> Bool) async {
    let passed: Bool
    do {
        passed = try await test()
    } catch {
        print("  \(RED)❌ FAIL\(NC)  [\(id)] \(name) — \(error)")
        results.append(TestResult(id: id, name: name, passed: false))
        return
    }
    
    if passed {
        print("  \(GRN)✅ PASS\(NC)  [\(id)] \(name)")
        results.append(TestResult(id: id, name: name, passed: true))
    } else {
        print("  \(RED)❌ FAIL\(NC)  [\(id)] \(name)")
        results.append(TestResult(id: id, name: name, passed: false))
    }
}

print("\(BOLD)\(CYN)══════════════════════════════════════════════════════\(NC)")
print("\(BOLD)  GaiaFTCL Swift TestRobit — GFTCL-SWIFT-OQ-001\(NC)")
print("\(BOLD)\(CYN)══════════════════════════════════════════════════════\(NC)\n")

print("\(BOLD)Suite 1: TauStateTests (τ sovereign time FFI)\(NC)")
TauStateTests.runAll()

print("\n\(BOLD)Suite 2: vQbitABITests (76-byte ABI + parser)\(NC)")
vQbitABITests.runAll()

print("\n\(BOLD)Suite 3: WalletTests (zero-PII, gaia1 prefix)\(NC)")
WalletTests.runAll()

print("\n\(BOLD)Suite 4: OwlProtocolTests (secp256k1 identity)\(NC)")
OwlProtocolTests.runAll()

print("\n\(BOLD)Suite 5: RendererFFITests (Metal FFI lifecycle)\(NC)")
RendererFFITests.runAll()

let passed = results.filter { $0.passed }.count
let failed = results.filter { !$0.passed }.count
let total  = results.count

print("\n\(BOLD)\(CYN)══════════════════════════════════════════════════════\(NC)")
print("\(BOLD)  TestRobit Result: \(passed)/\(total) passed, \(failed) failed\(NC)")

if failed == 0 {
    print("\(GRN)\(BOLD)  ✅ ALL TESTS PASSED — OQ receipt ready\(NC)")
} else {
    print("\(RED)\(BOLD)  ❌ FAILURES — resolve before OQ receipt\(NC)")
    for r in results where !r.passed {
        print("     → [\(r.id)] \(r.name)")
    }
}
print("\(BOLD)\(CYN)══════════════════════════════════════════════════════\(NC)\n")

// Write ALCOA+ receipt
do {
    let receiptPath = FileManager.default.currentDirectoryPath + "/../evidence/testrobit_receipt.json"
    let receiptURL = URL(fileURLWithPath: receiptPath)
    let evidenceDir = receiptURL.deletingLastPathComponent()
    
    try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
    
    // Generate operator_pubkey_hash from wallet
    let walletPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gaiaftcl/wallet.key")
    var operatorHash = "0000000000000000000000000000000000000000000000000000000000000000"
    if let walletData = try? Data(contentsOf: walletPath),
       let walletJSON = try? JSONSerialization.jsonObject(with: walletData) as? [String: Any],
       let walletAddr = walletJSON["wallet_address"] as? String {
        operatorHash = walletAddr.data(using: .utf8)?.sha256().hexString() ?? operatorHash
    }
    
    let receipt: [String: Any] = [
        "spec":                 "GFTCL-SWIFT-OQ-001",
        "phase":                "OQ",
        "cell":                 "GaiaFTCL",
        "gamp_category":        5,
        "timestamp":            ISO8601DateFormatter().string(from: Date()),
        "operator_pubkey_hash": operatorHash,
        "pii_stored":           false,
        "total_tests":          total,
        "passed":               passed,
        "failed":               failed,
        "skipped":              0,
        "status":               failed == 0 ? "PASS" : "FAIL",
        "training_mode":        true,
    ]
    
    let data = try JSONSerialization.data(withJSONObject: receipt, options: .prettyPrinted)
    try data.write(to: receiptURL)
    print("Receipt written to: \(receiptURL.path)")
} catch {
    print("Failed to write receipt: \(error)")
}

exit(failed == 0 ? 0 : 1)

// SHA256 helper
extension Data {
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
    
    func hexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
