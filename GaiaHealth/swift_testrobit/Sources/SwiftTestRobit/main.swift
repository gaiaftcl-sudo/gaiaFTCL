// SwiftTestRobit — McFusion Biologit Cell Test Harness
//
// Entry point. Runs all test suites and prints a GxP-formatted receipt.
// Zero-PII: this harness generates no personal information.
// All "patient" data is synthetic — derived from known literature compounds.
//
// Run: swift run SwiftTestRobit
// Or:  swift build && .build/debug/SwiftTestRobit
//
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import Foundation
import Dispatch
import CommonCrypto

// ── ANSI Colors ───────────────────────────────────────────────────────────────

let GRN  = "\u{001B}[0;32m"
let RED  = "\u{001B}[0;31m"
let BLU  = "\u{001B}[0;34m"
let YLW  = "\u{001B}[1;33m"
let CYN  = "\u{001B}[0;36m"
let BOLD = "\u{001B}[1m"
let NC   = "\u{001B}[0m"

// ── TestRobit Harness ─────────────────────────────────────────────────────────

struct TestResult {
    let id:      String
    let name:    String
    let passed:  Bool
    let message: String
}

var results: [TestResult] = []

func run(_ id: String, _ name: String, _ test: () throws -> Bool) {
    do {
        let passed = try test()
        let icon   = passed ? "\(GRN)✅ PASS\(NC)" : "\(RED)❌ FAIL\(NC)"
        print("  \(icon)  [\(id)] \(name)")
        results.append(TestResult(id: id, name: name, passed: passed, message: ""))
    } catch {
        print("  \(RED)❌ THROW\(NC) [\(id)] \(name): \(error)")
        results.append(TestResult(id: id, name: name, passed: false, message: "\(error)"))
    }
}

func run(_ id: String, _ name: String, _ test: () async throws -> Bool) async {
    do {
        let passed = try await test()
        let icon   = passed ? "\(GRN)✅ PASS\(NC)" : "\(RED)❌ FAIL\(NC)"
        print("  \(icon)  [\(id)] \(name)")
        results.append(TestResult(id: id, name: name, passed: passed, message: ""))
    } catch {
        print("  \(RED)❌ THROW\(NC) [\(id)] \(name): \(error)")
        results.append(TestResult(id: id, name: name, passed: false, message: "\(error)"))
    }
}

// ── Test Suites ───────────────────────────────────────────────────────────────

print("\n\(BOLD)\(CYN)══════════════════════════════════════════════════════\(NC)")
print("\(BOLD)\(CYN)  SwiftTestRobit — McFusion Biologit Cell\(NC)")
print("\(BOLD)\(CYN)  GaiaHealth v0.1.0  |  Zero-PII  |  GAMP 5 Cat 5\(NC)")
print("\(BOLD)\(CYN)══════════════════════════════════════════════════════\(NC)\n")

print("\(BOLD)Suite 1: FFI Bridge (BioState)\(NC)")
BioStateTests.runAll()

print("\n\(BOLD)Suite 2: State Machine\(NC)")
StateMachineTests.runAll()

print("\n\(BOLD)Suite 3: Zero-PII Wallet\(NC)")
WalletTests.runAll()

print("\n\(BOLD)Suite 4: M/I/A Epistemic Chain\(NC)")
EpistemicTests.runAll()

print("\n\(BOLD)Suite 5: WASM Constitutional Exports (contract tests)\(NC)")
let semaphore = DispatchSemaphore(value: 0)
Task {
    await ConstitutionalTests.runAll()
    semaphore.signal()
}
semaphore.wait()

// ── Receipt ───────────────────────────────────────────────────────────────────
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

// Write machine-readable receipt (ALCOA+ compliant per VMP §8.2)
do {
    let receiptPath = FileManager.default.currentDirectoryPath + "/../evidence/testrobit_receipt.json"
    let receiptURL = URL(fileURLWithPath: receiptPath)
    let evidenceDir = receiptURL.deletingLastPathComponent()
    
    // Ensure evidence directory exists
    try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
    
    // Generate operator_pubkey_hash from wallet (ALCOA+ Attributable)
    let walletPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gaiahealth/wallet.key")
    var operatorHash = "0000000000000000000000000000000000000000000000000000000000000000"
    if let walletData = try? Data(contentsOf: walletPath),
       let walletJSON = try? JSONSerialization.jsonObject(with: walletData) as? [String: Any],
       let walletAddr = walletJSON["wallet_address"] as? String {
        operatorHash = walletAddr.data(using: .utf8)?.sha256().hexString() ?? operatorHash
    }
    
    let receipt: [String: Any] = [
        "spec":                 "GAIA-HEALTH-TR-001",
        "phase":                "OQ",
        "cell":                 "GaiaHealth",
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

// SHA256 helper for wallet hash
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
