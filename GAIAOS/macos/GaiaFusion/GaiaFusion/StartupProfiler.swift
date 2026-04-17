import Foundation

/// Startup telemetry profiler for measuring component initialization times
/// Tracks critical path: LocalServer → WASM → Metal → WebView → Ready
@MainActor
final class StartupProfiler {
    static let shared = StartupProfiler()
    
    private var startTime: Date?
    private var checkpoints: [(String, TimeInterval)] = []
    private var isComplete = false
    
    private init() {}
    
    /// Start profiling from app launch
    func start() {
        startTime = Date()
        checkpoints = []
        isComplete = false
        checkpoint("app_launch")
    }
    
    /// Record a checkpoint with elapsed time from start
    func checkpoint(_ name: String) {
        guard let start = startTime, !isComplete else { return }
        let elapsed = Date().timeIntervalSince(start)
        checkpoints.append((name, elapsed))
        print("📊 Startup: \(name) at \(String(format: "%.3f", elapsed))s")
    }
    
    /// Mark startup as complete and generate report
    func complete() {
        guard !isComplete else { return }
        isComplete = true
        checkpoint("ready_interactive")
        generateReport()
    }
    
    /// Generate JSON report for evidence
    private func generateReport() {
        guard let start = startTime else { return }
        
        let totalTime = Date().timeIntervalSince(start)
        let report: [String: Any] = [
            "total_startup_time_seconds": totalTime,
            "target_time_seconds": 2.0,
            "meets_target": totalTime < 2.0,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "checkpoints": checkpoints.map { ["name": $0.0, "elapsed_seconds": $0.1] }
        ]
        
        // Print summary
        print("\n📊 STARTUP PERFORMANCE SUMMARY")
        print("════════════════════════════════════════")
        print("Total Time: \(String(format: "%.3f", totalTime))s")
        print("Target: 2.0s")
        print("Status: \(totalTime < 2.0 ? "✅ PASS" : "❌ FAIL")")
        print("\nCheckpoints:")
        for (name, elapsed) in checkpoints {
            print("  • \(name): \(String(format: "%.3f", elapsed))s")
        }
        print("════════════════════════════════════════\n")
        
        // Write to evidence directory
        saveReport(report)
    }
    
    /// Save report to evidence/performance/
    private func saveReport(_ report: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) else {
            print("⚠️ Failed to serialize startup report")
            return
        }
        
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "startup_profile_\(timestamp).json"
        
        // Try workspace evidence directory first
        let workspacePath = FileManager.default.currentDirectoryPath
        let evidenceDir = "\(workspacePath)/evidence/performance"
        
        // Create directory if needed
        try? FileManager.default.createDirectory(atPath: evidenceDir, withIntermediateDirectories: true)
        
        let filePath = "\(evidenceDir)/\(filename)"
        
        do {
            try jsonData.write(to: URL(fileURLWithPath: filePath))
            print("📝 Startup report saved: \(filePath)")
        } catch {
            print("⚠️ Failed to save startup report: \(error)")
            // Fallback to tmp
            let tmpPath = "/tmp/\(filename)"
            try? jsonData.write(to: URL(fileURLWithPath: tmpPath))
            print("📝 Startup report saved to fallback: \(tmpPath)")
        }
    }
    
    /// Get elapsed time since start
    func elapsed() -> TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
}
