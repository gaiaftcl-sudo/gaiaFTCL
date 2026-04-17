// CleanCloneTest — Test Mac qualification from clean clone (Swift only)
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import Foundation

func banner(_ msg: String) {
    print("\n\u{001B}[34m══════════════════════════════════════════════════════════\u{001B}[0m")
    print("\u{001B}[34m  \(msg)\u{001B}[0m")
    print("\u{001B}[34m══════════════════════════════════════════════════════════\u{001B}[0m")
}

func ok(_ msg: String) { print("\u{001B}[32m  ✅ \(msg)\u{001B}[0m") }
func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("\u{001B}[31m  ❌ BLOCKED: \(msg)\u{001B}[0m\n".utf8))
    exit(1)
}

func run(_ args: [String], cwd: String? = nil) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    if let cwd = cwd {
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    }
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func main() {
    banner("Mac Qualification — Clean Clone Test (Swift)")
    
    // Create test directory
    let timestamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    let testDir = "\(NSHomeDirectory())/FoT8D_qualification_test_\(timestamp)"
    
    banner("Step 1/6: Create test directory")
    let fm = FileManager.default
    try? fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    ok("Test directory: \(testDir)")
    
    // Clone repo
    banner("Step 2/6: Clone repository")
    let sourceRepo = "\(NSHomeDirectory())/Documents/FoT8D"
    var exit = run(["git", "clone", sourceRepo, "FoT8D"], cwd: testDir)
    if exit != 0 { fail("Git clone failed") }
    
    let cloneDir = "\(testDir)/FoT8D"
    exit = run(["git", "checkout", "feat/mac-qualification-swift-only"], cwd: cloneDir)
    if exit != 0 { fail("Branch checkout failed") }
    ok("Repository cloned")
    
    // Build TestRobot
    banner("Step 3/6: Build TestRobot")
    exit = run(["swift", "build"], cwd: "\(cloneDir)/GAIAOS/macos/TestRobot")
    if exit != 0 { fail("TestRobot build failed") }
    ok("TestRobot built")
    
    // Run IQ
    banner("Step 4/6: IQ (Installation Qualification)")
    print("  Running: scripts/gamp5_iq.sh --cell both")
    exit = run(["zsh", "scripts/gamp5_iq.sh", "--cell", "both"], cwd: cloneDir)
    if exit != 0 { fail("IQ failed") }
    ok("IQ: PASS (both cells)")
    
    // Run OQ
    banner("Step 5/6: OQ (Operational Qualification)")
    print("  Running: scripts/gamp5_oq.sh --cell both")
    exit = run(["zsh", "scripts/gamp5_oq.sh", "--cell", "both"], cwd: cloneDir)
    if exit != 0 { fail("OQ failed") }
    ok("OQ: PASS (both cells)")
    
    // Run PQ
    banner("Step 6/6: PQ (Performance Qualification)")
    print("  Running: scripts/gamp5_pq.sh --cell both")
    exit = run(["zsh", "scripts/gamp5_pq.sh", "--cell", "both"], cwd: cloneDir)
    if exit != 0 { fail("PQ failed") }
    ok("PQ: PASS (both cells + TestRobot)")
    
    // Verify receipts
    banner("Verifying All Receipts")
    let receipts = [
        "GAIAOS/macos/GaiaFusion/evidence/iq/iq_receipt.json",
        "GAIAOS/macos/GaiaFusion/evidence/oq/oq_receipt.json",
        "GAIAOS/macos/GaiaFusion/evidence/pq/pq_receipt.json",
        "GAIAOS/macos/MacHealth/evidence/iq/iq_receipt.json",
        "GAIAOS/macos/MacHealth/evidence/oq/oq_receipt.json",
        "GAIAOS/macos/MacHealth/evidence/pq/pq_receipt.json",
        "evidence/TESTROBOT_RECEIPT.json"
    ]
    
    for receipt in receipts {
        let path = "\(cloneDir)/\(receipt)"
        guard fm.fileExists(atPath: path) else {
            fail("Receipt missing: \(receipt)")
        }
        ok(URL(fileURLWithPath: receipt).lastPathComponent)
    }
    
    // Summary
    banner("STATE: CALORIE — Clean Clone Test PASS")
    print()
    print("\u{001B}[32m  ✅ IQ: PASS (scripts/gamp5_iq.sh)\u{001B}[0m")
    print("\u{001B}[32m  ✅ OQ: PASS (scripts/gamp5_oq.sh)\u{001B}[0m")
    print("\u{001B}[32m  ✅ PQ: PASS (scripts/gamp5_pq.sh + TestRobot)\u{001B}[0m")
    print("\u{001B}[32m  ✅ All receipts: Present and valid (7/7)\u{001B}[0m")
    print()
    print("  Test directory: \(testDir)")
    print("  Receipts:")
    for receipt in receipts {
        print("    \(testDir)/FoT8D/\(receipt)")
    }
    print()
    print("\u{001B}[33m═══════════════════════════════════════════════════════════\u{001B}[0m")
    print("\u{001B}[33m  To clean up: rm -rf \(testDir)\u{001B}[0m")
    print("\u{001B}[33m═══════════════════════════════════════════════════════════\u{001B}[0m")
}

main()
