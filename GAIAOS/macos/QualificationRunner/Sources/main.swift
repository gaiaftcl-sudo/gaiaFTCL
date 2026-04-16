// QualificationRunner — Orchestrates MacFusion + MacHealth + TestRobot
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

func runExecutable(_ path: String) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func main() {
    banner("QualificationRunner — Master Orchestrator")
    
    let repoRoot = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    
    print("  Repo: \(repoRoot)")
    
    // ═══════════════════════════════════════════════════════════════
    // 1. MacFusion IQ/OQ/PQ
    // ═══════════════════════════════════════════════════════════════
    
    banner("Step 1/3: MacFusion Qualification")
    let mfQualPath = "\(repoRoot)/GAIAOS/macos/MacFusionQualification/.build/debug/MacFusionQualification"
    let mfExit = runExecutable(mfQualPath)
    if mfExit != 0 { fail("MacFusion qualification failed") }
    ok("MacFusion: IQ → OQ → PQ COMPLETE")
    
    // ═══════════════════════════════════════════════════════════════
    // 2. MacHealth IQ/OQ/PQ
    // ═══════════════════════════════════════════════════════════════
    
    banner("Step 2/3: MacHealth Qualification")
    let mhQualPath = "\(repoRoot)/GAIAOS/macos/MacHealthQualification/.build/debug/MacHealthQualification"
    let mhExit = runExecutable(mhQualPath)
    if mhExit != 0 { fail("MacHealth qualification failed") }
    ok("MacHealth: IQ → OQ → PQ COMPLETE")
    
    // ═══════════════════════════════════════════════════════════════
    // 3. TestRobot (live test)
    // ═══════════════════════════════════════════════════════════════
    
    banner("Step 3/3: TestRobot (live test)")
    let testRobotPath = "\(repoRoot)/GAIAOS/macos/TestRobot/.build/debug/TestRobot"
    let trExit = runExecutable(testRobotPath)
    if trExit != 0 { fail("TestRobot failed") }
    ok("TestRobot: PASS (live test)")
    
    // ═══════════════════════════════════════════════════════════════
    // Final Summary
    // ═══════════════════════════════════════════════════════════════
    
    banner("STATE: CALORIE — All Qualification Complete")
    print("\u{001B}[32m  ✅ MacFusion: IQ/OQ/PQ PASS\u{001B}[0m")
    print("\u{001B}[32m  ✅ MacHealth: IQ/OQ/PQ PASS\u{001B}[0m")
    print("\u{001B}[32m  ✅ TestRobot: PASS (live)\u{001B}[0m")
    print()
    print("  Receipts:")
    print("    \(repoRoot)/GAIAOS/macos/GaiaFusion/evidence/")
    print("    \(repoRoot)/GAIAOS/macos/MacHealth/evidence/")
    print("    \(repoRoot)/evidence/TESTROBOT_RECEIPT.json")
}

main()
