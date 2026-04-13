import Foundation

public struct ProjectionState: Codable, Equatable {
    public let meshHealthy: Int
    public let meshTotal: Int
    public let natsConnected: Bool
    public let vqbitDelta: Double
    public let lastUpdatedUtc: String
    public let swapsRecent: [SwapState]

    public init(
        meshHealthy: Int,
        meshTotal: Int,
        natsConnected: Bool,
        vqbitDelta: Double,
        lastUpdatedUtc: String,
        swapsRecent: [SwapState] = []
    ) {
        self.meshHealthy = meshHealthy
        self.meshTotal = meshTotal
        self.natsConnected = natsConnected
        self.vqbitDelta = vqbitDelta
        self.lastUpdatedUtc = lastUpdatedUtc
        self.swapsRecent = swapsRecent
    }

    public var meshHealthText: String {
        "\(meshHealthy)/\(meshTotal)"
    }

    public var vqbitText: String {
        String(format: "%.3f", vqbitDelta)
    }
}
