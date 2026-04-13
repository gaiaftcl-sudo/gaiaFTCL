import Foundation

@MainActor
final class SSHService {
    func canConnect(host: String, keyPath: String, user: String) async -> Bool {
        let testCommand = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-i", keyPath, "\(user)@\(host)", "exit"]
        let result = await run(command: testCommand)
        return result.exitCode == 0
    }

    func runSSHCommand(host: String, keyPath: String, user: String, command: String) async -> (exitCode: Int, output: String) {
        let args = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-i", keyPath, "\(user)@\(host)", command]
        return await run(command: args)
    }

    private func run(command: [String]) async -> (exitCode: Int, output: String) {
        let queue = DispatchQueue(label: "ssh.service.shell")
        return await withCheckedContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.first ?? "ssh")
                process.arguments = Array(command.dropFirst())
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = outPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    continuation.resume(returning: (Int(process.terminationStatus), output))
                } catch {
                    continuation.resume(returning: (127, String(describing: error)))
                }
            }
        }
    }
}
