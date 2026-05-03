import Foundation
import GaiaFTCLCore

public struct GAMPReceipt: Sendable, Encodable {
    public let testID: String
    public let passed: Bool
    public let timestamp: Date

    public init(testID: String, passed: Bool) {
        self.testID = testID
        self.passed = passed
        self.timestamp = Date()
    }
}

public func writeReceipt(_ receipt: GAMPReceipt, to directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(receipt)
    let url = directory.appendingPathComponent("\(receipt.testID).json")
    try data.write(to: url, options: .atomic)
}

// MARK: — QualReceipt

public struct QualReceipt: Sendable, Encodable {
    public enum Phase: String, Sendable, Encodable {
        case mq = "MQ"
        case iq = "IQ"
        case oq = "OQ"
        case pq = "PQ"
    }

    public struct TestResult: Sendable, Encodable {
        public let id: String
        public let name: String
        public let passed: Bool
        public let durationMs: Double
        public let detail: String

        public init(id: String, name: String, passed: Bool, durationMs: Double, detail: String) {
            self.id = id
            self.name = name
            self.passed = passed
            self.durationMs = durationMs
            self.detail = detail
        }
    }

    public let phase: Phase
    public let platform: String
    public let swiftVersion: String
    public let testResults: [TestResult]
    public let overallStatus: TerminalState
    public let timestamp: String

    public init(phase: Phase, platform: String, swiftVersion: String, testResults: [TestResult]) {
        self.phase = phase
        self.platform = platform
        self.swiftVersion = swiftVersion
        self.testResults = testResults
        self.overallStatus = testResults.allSatisfy(\.passed) ? .calorie : .blocked
        self.timestamp = ISO8601DateFormatter().string(from: Date())
    }

    public func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        let safeTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let name = "\(phase.rawValue)-\(safeTimestamp).json"
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: — WorkspaceLocator

public enum WorkspaceLocator {
    public static func packageRoot(from filePath: String) -> URL? {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fs = FileManager.default
        for _ in 0..<15 {
            if fs.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    public static func receiptOutputDirectory(from filePath: String) -> URL? {
        guard let root = packageRoot(from: filePath) else { return nil }
        return root.appendingPathComponent("qualification_receipts", isDirectory: true)
    }
}
