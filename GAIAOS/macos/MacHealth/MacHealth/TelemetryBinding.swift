import Foundation

public struct TelemetryTick: Codable {
    public let type: String = "telemetry.tick"
    public let timestamp: String
    public let run_id: String
    public let parent_hash: String
    public let substrate_sha256: String
    public let state: String
    public let epistemic_tag: String
    public let measurements: [Measurement]
    public let cell_signature: String
    public let transducer_signatures: [String]
    
    public struct Measurement: Codable {
        public let id: String
        public let value: Double
        public let unit: String
        public let provenance: String
    }
    
    public init(
        timestamp: Date,
        runId: String,
        parentHash: String,
        substrateSha256: String,
        state: String,
        epistemicTag: String,
        measurements: [Measurement],
        cellSignature: String,
        transducerSignatures: [String]
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.string(from: timestamp)
        self.run_id = runId
        self.parent_hash = parentHash
        self.substrate_sha256 = substrateSha256
        self.state = state
        self.epistemic_tag = epistemicTag
        self.measurements = measurements
        self.cell_signature = cellSignature
        self.transducer_signatures = transducerSignatures
    }
    
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public class TelemetryBinder {
    public static func createSILTick(
        runId: String,
        parentHash: String,
        substrateSha256: String,
        state: String,
        measurements: [TelemetryTick.Measurement],
        cellSignature: String,
        transducerSignatures: [String]
    ) -> TelemetryTick {
        // Enforce (M_SIL) tag distinction during SIL execution
        let epistemicTag = "(M_SIL)"
        
        return TelemetryTick(
            timestamp: Date(),
            runId: runId,
            parentHash: parentHash,
            substrateSha256: substrateSha256,
            state: state,
            epistemicTag: epistemicTag,
            measurements: measurements,
            cellSignature: cellSignature,
            transducerSignatures: transducerSignatures
        )
    }
}
