import Foundation

public struct GAMPWrapper {
    public static func runIQ() throws -> String {
        return try runScript(name: "gamp5_iq.sh", args: ["--cell", "both"], iteration: 1)
    }
    
    public static func runOQ() throws -> String {
        return try runScript(name: "gamp5_oq.sh", args: ["--cell", "both"], iteration: 2)
    }
    
    public static func runPQ() throws -> String {
        return try runScript(name: "gamp5_pq.sh", args: ["--cell", "both"], iteration: 3)
    }
    
    private static func runScript(name: String, args: [String], iteration: Int) throws -> String {
        // Enforce Phi-scaling invariant on qualification gates to prevent rhythmic "Human Bell" loops
        let stagger = vQbitScalingProvider.generateStaggerInterval(iteration: iteration)
        FileHandle.standardError.write(Data("\n[vQbitScalingProvider] Enforcing stochastic Phi-stagger: sleeping for \(String(format: "%.3f", stagger))s...\n".utf8))
        Thread.sleep(forTimeInterval: stagger)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        
        var scriptPath = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "scripts")?.path
        if scriptPath == nil || !FileManager.default.fileExists(atPath: scriptPath!) {
            let possiblePaths = [
                "../scripts/\(name)",
                "scripts/\(name)",
                "../../scripts/\(name)"
            ]
            for path in possiblePaths {
                if FileManager.default.fileExists(atPath: path) {
                    scriptPath = path
                    break
                }
            }
        }
        
        guard let finalPath = scriptPath else {
            throw NSError(domain: "GAMPWrapper", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find script \(name) in known paths"])
        }
        
        process.arguments = ["zsh", finalPath] + args
        
        // Pass stdin so 'read -p' works for human bells
        process.standardInput = FileHandle.standardInput
        
        // Route script's stdout/stderr to the CLI's stderr to preserve the CALORIE/CURE/REFUSED stdout contract
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "GAMPWrapper", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Script \(name) failed with exit code \(process.terminationStatus)"])
        }
        
        return ""
    }
}
