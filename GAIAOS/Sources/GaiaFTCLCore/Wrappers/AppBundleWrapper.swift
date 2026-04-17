import Foundation

public struct AppBundleWrapper {
    public static func runFusionGame(_ game: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        
        let appPath = "GAIAOS/macos/GaiaFusion/GaiaFusion.app"
        process.arguments = ["-W", "-n", "-a", appPath, "--args", "--game", "\(game)"]
        
        // Route to stderr to preserve stdout contract
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        
        let startTime = Date().addingTimeInterval(-2)
        
        try process.run()
        process.waitUntilExit()
        
        // Check for crash logs created after startTime
        let fm = FileManager.default
        let crashLogsDir = NSHomeDirectory().appending("/Library/Logs/DiagnosticReports")
        if let files = try? fm.contentsOfDirectory(atPath: crashLogsDir) {
            let recentCrashes = files.filter { $0.hasPrefix("GaiaFusion") && $0.hasSuffix(".ips") }
            for file in recentCrashes {
                let path = crashLogsDir.appending("/\(file)")
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let creationDate = attrs[.creationDate] as? Date,
                   creationDate > startTime {
                    throw NSError(domain: "AppBundleWrapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fusion app crashed (crash log found: \(file))"])
                }
            }
        }
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "AppBundleWrapper", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Fusion app failed to launch with exit code \(process.terminationStatus)"])
        }
        
        return ""
    }
}
