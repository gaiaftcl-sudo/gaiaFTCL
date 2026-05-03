import Foundation
import GaiaGateKit

let args = CommandLine.arguments
let repoRoot: String
if let idx = args.firstIndex(of: "--repo-root"), idx + 1 < args.count {
    repoRoot = args[idx + 1]
} else {
    repoRoot = FileManager.default.currentDirectoryPath
}

let rtmPath = repoRoot + "/docs/REQUIREMENTS_TRACEABILITY_MATRIX.json"
guard FileManager.default.fileExists(atPath: rtmPath) else {
    fputs("TERMINAL STATE: BLOCKED — RTM not found at \(rtmPath)\n", stderr)
    exit(1)
}
guard let data = FileManager.default.contents(atPath: rtmPath),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      json["requirements"] != nil else {
    fputs("TERMINAL STATE: BLOCKED — RTM malformed or missing requirements key\n", stderr)
    exit(1)
}
print("TERMINAL STATE: CALORIE")
exit(0)
