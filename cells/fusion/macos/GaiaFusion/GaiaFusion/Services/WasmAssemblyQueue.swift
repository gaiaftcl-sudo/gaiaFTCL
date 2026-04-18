import Foundation

enum WasmAssemblyQueueError: LocalizedError {
    case queueLocked
    case executionFailure(String)

    var errorDescription: String? {
        switch self {
        case .queueLocked:
            return "ASM Queue Locked. Dropping overlapping language game."
        case let .executionFailure(output):
            return output
        }
    }
}

/// Dedicated serial queue for WASM assembly language games.
/// Runs at .utility QoS so UI/Metal rendering keeps priority.
final class WasmAssemblyQueue: @unchecked Sendable {
    private let asmQueue = DispatchQueue(label: "com.gaiaftcl.asm.compiler", qos: .utility)
    private var isCompiling = false

    func dispatchCompilation(workingDirectory: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            asmQueue.async {
                guard !self.isCompiling else {
                    continuation.resume(throwing: WasmAssemblyQueueError.queueLocked)
                    return
                }
                self.isCompiling = true
                defer { self.isCompiling = false }

                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["npm", "run", "build:wasm"]
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: WasmAssemblyQueueError.executionFailure(output))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
