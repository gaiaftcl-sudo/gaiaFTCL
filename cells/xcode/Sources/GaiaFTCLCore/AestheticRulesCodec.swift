import CryptoKit
import Foundation

/// Canonical **`aesthetic_rules_json`** envelope — keys sorted on encode via **`JSONEncoder.outputFormatting = [.sortedKeys]`**.
public struct AestheticRulesEnvelope: Codable, Sendable, Equatable {
    public let schema_version: Int
    public struct Weights: Codable, Sendable, Equatable {
        public let s1_weight: Double
        public let s2_weight: Double
        public let s3_weight: Double
        public let s4_weight: Double

        public init(s1_weight: Double, s2_weight: Double, s3_weight: Double, s4_weight: Double) {
            self.s1_weight = s1_weight
            self.s2_weight = s2_weight
            self.s3_weight = s3_weight
            self.s4_weight = s4_weight
        }
    }

    public let weights: Weights

    public init(schema_version: Int, weights: Weights) {
        self.schema_version = schema_version
        self.weights = weights
    }

    public static func bootstrapDefaults() -> AestheticRulesEnvelope {
        AestheticRulesEnvelope(
            schema_version: 1,
            weights: Weights(s1_weight: 0.5, s2_weight: 0.5, s3_weight: 0.5, s4_weight: 0.5)
        )
    }
}

public enum AestheticRulesCodec {
    public static func canonicalJSONData(_ env: AestheticRulesEnvelope) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(env)
    }

    public static func canonicalJSONString(_ env: AestheticRulesEnvelope) throws -> String {
        guard let s = String(data: try canonicalJSONData(env), encoding: .utf8) else {
            throw NSError(domain: "AestheticRulesCodec", code: 1, userInfo: [NSLocalizedDescriptionKey: "utf8"])
        }
        return s
    }

    public static func sha256Hex(ofCanonicalJSON utf8: Data) -> String {
        SHA256.hash(data: utf8).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(_ env: AestheticRulesEnvelope) throws -> String {
        sha256Hex(ofCanonicalJSON: try canonicalJSONData(env))
    }

    public static func decode(from json: String) throws -> AestheticRulesEnvelope {
        guard let data = json.data(using: .utf8) else {
            throw NSError(domain: "AestheticRulesCodec", code: 2, userInfo: [NSLocalizedDescriptionKey: "decode utf8"])
        }
        return try JSONDecoder().decode(AestheticRulesEnvelope.self, from: data)
    }
}
