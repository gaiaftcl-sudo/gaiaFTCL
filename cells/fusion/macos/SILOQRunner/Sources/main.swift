// SILOQRunner — Software-in-the-Loop OQ Orchestrator (Swift)
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
    banner("Mac Qualification — SIL OQ Runner (Swift)")
    
    let currentPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // SILOQRunner
        .deletingLastPathComponent() // macos
        .deletingLastPathComponent() // GAIAOS
    
    let repoRoot = currentPath.path
    print("  Repo root: \(repoRoot)")
    
    let filters = [
        "testZMQWireFormatHeader",
        "testTelemetryTickSchemaBinding",
        "testGAMP5GamesNarrativeReport"
    ]
    
    banner("Step 1/1: Execute SIL OQ Swift Tests")
    let macHealthDir = "\(repoRoot)/macos/MacHealth"
    
    var allPassed = true
    for filter in filters {
        print("\n  Running: swift test --filter \(filter)")
        let exitCode = run(["swift", "test", "--disable-sandbox", "--filter", filter], cwd: macHealthDir)
        if exitCode != 0 {
            print("\u{001B}[31m  ❌ \(filter) FAILED\u{001B}[0m")
            allPassed = false
        } else {
            ok("\(filter) PASSED")
        }
    }
    
    if !allPassed {
        fail("One or more SIL OQ tests failed.")
    }
    
    banner("STATE: CALORIE — SIL OQ Complete")
    print("\u{001B}[32m  ✅ All SIL OQ Swift tests passed.\u{001B}[0m")
}

main()
