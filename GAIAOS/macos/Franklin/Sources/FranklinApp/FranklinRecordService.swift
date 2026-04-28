import AVFoundation
import Foundation

struct FranklinRecordRequest {
    let outputURL: URL
    let tau: String
    let lgID: String
}

enum FranklinRecordState: String {
    case idle
    case recording
}

@MainActor
final class FranklinRecordService {
    static let shared = FranklinRecordService()

    private(set) var state: FranklinRecordState = .idle
    private var currentRequest: FranklinRecordRequest?
    private var sessionStart: Date?

    private init() {}

    func start(_ request: FranklinRecordRequest) throws {
        guard state == .idle else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: request.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        currentRequest = request
        sessionStart = Date()
        state = .recording
    }

    func stop() throws -> URL? {
        guard state == .recording, let request = currentRequest else { return nil }
        let startedAt = sessionStart ?? Date()
        let stoppedAt = Date()
        let body: [String: Any] = [
            "tau": request.tau,
            "lg_id": request.lgID,
            "state": "PASS",
            "started_at": ISO8601DateFormatter().string(from: startedAt),
            "stopped_at": ISO8601DateFormatter().string(from: stoppedAt),
            "duration_ms": Int(stoppedAt.timeIntervalSince(startedAt) * 1000),
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        try data.write(to: request.outputURL, options: .atomic)
        currentRequest = nil
        sessionStart = nil
        state = .idle
        return request.outputURL
    }
}
