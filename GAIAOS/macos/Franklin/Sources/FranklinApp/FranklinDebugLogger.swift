import Foundation

enum FranklinDebugLogger {
    private static let logPath = "/Users/richardgillespie/Documents/GaiaFTCL-MacCells/.cursor/debug-e2235d.log"

    static func log(
        runId: String,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String]
    ) {
        var payload: [String: Any] = [
            "sessionId": "e2235d",
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        payload["id"] = "log_\(payload["timestamp"] ?? 0)_\(UUID().uuidString)"
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: encoded, encoding: .utf8)
        else { return }
        let url = URL(fileURLWithPath: logPath)
        let lineData = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: lineData)
        } else {
            try? lineData.write(to: url, options: .atomic)
        }
    }
}
