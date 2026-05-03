import Foundation
import CryptoKit

// MARK: - Terminal State

public enum TerminalState: String, Sendable, Codable, Hashable {
    case calorie  = "CALORIE"
    case cure     = "CURE"
    case refused  = "REFUSED"
    case blocked  = "BLOCKED"
}

// MARK: - Terminal Wire Bridge

public enum TerminalWireBridge {
    /// Maps TerminalState → C4ProjectionWire terminal byte (1-based visual codes).
    public static func visualCode(for state: TerminalState) -> UInt8 {
        switch state {
        case .calorie: return 0x01
        case .cure:    return 0x02
        case .refused: return 0x03
        case .blocked: return 0x04
        }
    }

    public static func terminalState(fromVisualCode code: UInt8) -> TerminalState {
        switch code {
        case 0x01: return .calorie
        case 0x02: return .cure
        case 0x03: return .refused
        default:   return .blocked
        }
    }
}

// MARK: - Language Game Contract Document (JSON-decodable contract row)

public struct LanguageGameContractDocument: Codable, Sendable {
    public let game_id: String
    public let domain: String
    public let prim_paths: [String]
    public let constitutional_threshold_calorie: Double
    public let constitutional_threshold_cure: Double
    public let algorithm_count: Int

    public init(
        game_id: String,
        domain: String,
        prim_paths: [String],
        constitutional_threshold_calorie: Double,
        constitutional_threshold_cure: Double,
        algorithm_count: Int = 0
    ) {
        self.game_id = game_id
        self.domain = domain
        self.prim_paths = prim_paths
        self.constitutional_threshold_calorie = constitutional_threshold_calorie
        self.constitutional_threshold_cure = constitutional_threshold_cure
        self.algorithm_count = algorithm_count
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game_id = try c.decode(String.self, forKey: .game_id)
        domain = try c.decode(String.self, forKey: .domain)
        prim_paths = try c.decode([String].self, forKey: .prim_paths)
        constitutional_threshold_calorie = try c.decode(Double.self, forKey: .constitutional_threshold_calorie)
        constitutional_threshold_cure = try c.decode(Double.self, forKey: .constitutional_threshold_cure)
        algorithm_count = (try? c.decode(Int.self, forKey: .algorithm_count)) ?? 0
    }
}

// MARK: - Language Game Contract Seed

public struct LanguageGameContractSeed: Encodable, Sendable {
    public let game_id: String
    public let domain: String
    public let prim_paths: [String]
    public let constitutional_threshold_calorie: Double
    public let constitutional_threshold_cure: Double
    public let sha256: String

    public static let fusionGameID = "FUSION-001"
    public static let healthGameID = "HEALTH-001"

    public static func fusionContract(createdAtISO: String) throws -> LanguageGameContractSeed {
        let paths = ["/World/Domains/Fusion/Tokamak",
                     "/World/Domains/Fusion/StellaratorHD",
                     "/World/Domains/Fusion/InertialConfinement",
                     "/World/Domains/Fusion/MagnetoInertial",
                     "/World/Domains/Fusion/FieldReversed",
                     "/World/Domains/Fusion/CompactFusion"]
        return try seed(gameID: fusionGameID, domain: "fusion", paths: paths,
                        calorie: 0.82, cure: 0.55)
    }

    public static func healthContract(createdAtISO: String) throws -> LanguageGameContractSeed {
        let paths = ["/World/Domains/Health/Protocol"]
        return try seed(gameID: healthGameID, domain: "health", paths: paths,
                        calorie: 0.80, cure: 0.50)
    }

    private static func seed(gameID: String, domain: String, paths: [String],
                              calorie: Double, cure: Double) throws -> LanguageGameContractSeed {
        let doc = LanguageGameContractDocument(
            game_id: gameID,
            domain: domain,
            prim_paths: paths,
            constitutional_threshold_calorie: calorie,
            constitutional_threshold_cure: cure
        )
        let data = try JSONEncoder().encode(doc)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return LanguageGameContractSeed(
            game_id: gameID,
            domain: domain,
            prim_paths: paths,
            constitutional_threshold_calorie: calorie,
            constitutional_threshold_cure: cure,
            sha256: hex
        )
    }
}

// MARK: - NATSConfiguration extensions

extension NATSConfiguration {
    /// Seconds before a τ reading is considered stale (10 minutes = 2 × Bitcoin block interval minimum).
    public static let tauStalenessSeconds: TimeInterval = 600
}
