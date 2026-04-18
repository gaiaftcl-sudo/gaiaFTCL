import Foundation

public enum SwapLifecycle: String, Codable {
    case idle = "idle"
    case requested = "requested"
    case draining = "draining"
    case committed = "committed"
    case verified = "verified"
    case failed = "failed"
    case rollback = "rollback"
}

public struct SwapState: Identifiable, Codable, Equatable {
    public let id: UUID
    public let requestID: String
    public let cellID: String
    public let inputPlantType: String
    public let outputPlantType: String
    public let createdAtUtc: String
    public var lifecycle: SwapLifecycle
    public var detail: String?

    public init(
        requestID: String,
        cellID: String,
        inputPlantType: String,
        outputPlantType: String,
        createdAtUtc: String,
        lifecycle: SwapLifecycle = .requested,
        detail: String? = nil
    ) {
        self.id = UUID()
        self.requestID = requestID
        self.cellID = cellID
        self.inputPlantType = inputPlantType
        self.outputPlantType = outputPlantType
        self.createdAtUtc = createdAtUtc
        self.lifecycle = lifecycle
        self.detail = detail
    }

    public mutating func advance() {
        switch lifecycle {
        case .idle:
            lifecycle = .requested
        case .requested:
            lifecycle = .draining
        case .draining:
            lifecycle = .committed
        case .committed:
            lifecycle = .verified
        case .verified, .failed, .rollback:
            break
        }
    }
    
    /// Trigger rollback to previous plant state
    public mutating func triggerRollback() {
        lifecycle = .rollback
    }
}
