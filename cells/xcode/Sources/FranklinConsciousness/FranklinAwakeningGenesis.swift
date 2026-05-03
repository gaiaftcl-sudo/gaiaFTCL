import CryptoKit
import Foundation
import GaiaFTCLCore

/// First-wake genesis: learning receipt + catalog memories + self-model baseline (**CALORIE** preflight only).
public enum FranklinAwakeningGenesis {
    private static let genesisReceiptRowID = "gaiaftcl-genesis-receipt-v1"
    private static let genesisSelfModelRowID = "gaiaftcl-franklin-selfmodel-genesis-v1"
    private static let catalogIngestDefaultsKey = "GaiaFTCLFranklinGenesisCatalogIngested.v1"

    public static func performIfCalorie(
        sessionID: String,
        preflight: FranklinConsciousnessActor.PreflightReport
    ) async {
        guard preflight.terminalState == .calorie else { return }

        let fusionGames = LanguageGameCatalog.games(for: .fusion)
        let healthGames = LanguageGameCatalog.games(for: .health)
        let fusionVer = fusionGames.map(\.id).joined(separator: "|").data(using: .utf8).map { Self.sha256Hex($0) } ?? ""
        let healthVer = healthGames.map(\.id).joined(separator: "|").data(using: .utf8).map { Self.sha256Hex($0) } ?? ""

        let natsURL = NATSConfiguration.vqbitNATSURL
        let awakenISO = preflight.timestampUTC

        struct GenesisPayload: Codable, Sendable {
            let receipt_id: String
            let kind: String
            let awaken_timestamp: String
            let preflight_terminal_state: String
            let fusion_catalog_version: String
            let health_protocol_version: String
            let nats_url: String
            let substrate_schema_version: String
        }

        let payloadCore = GenesisPayload(
            receipt_id: genesisReceiptRowID,
            kind: "genesis",
            awaken_timestamp: awakenISO,
            preflight_terminal_state: preflight.terminalState.rawValue,
            fusion_catalog_version: fusionVer,
            health_protocol_version: healthVer,
            nats_url: natsURL,
            substrate_schema_version: "v3_genesis_receipt"
        )

        let payloadData = (try? JSONEncoder().encode(payloadCore)) ?? Data()
        let canonical = Self.sha256Hex(payloadData)
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"

        await FranklinSubstrate.shared.insertGenesisLearningReceiptIfAbsent(
            id: genesisReceiptRowID,
            sessionID: sessionID,
            terminal: TerminalState.calorie.rawValue,
            receiptPath: "",
            receiptSha256: canonical,
            timestampISO: awakenISO,
            kind: "genesis",
            payloadJSON: payloadJSON,
            canonicalSha256: canonical
        )

        await FranklinSubstrate.shared.seedLanguageGameContracts(timestampISO: awakenISO)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: catalogIngestDefaultsKey) {
            let c4 = await C4MemoryStore.shared.currentState()
            for g in fusionGames {
                await C4MemoryStore.shared.record(
                    C4MemoryEvent(
                        id: "genesis-fusion-\(g.id)",
                        sessionID: sessionID,
                        kind: .fusionCatalog,
                        text: "\(g.id): \(g.title)",
                        c4Snapshot: c4,
                        terminalState: .calorie
                    )
                )
            }
            for g in healthGames {
                await C4MemoryStore.shared.record(
                    C4MemoryEvent(
                        id: "genesis-health-\(g.id)",
                        sessionID: sessionID,
                        kind: .healthProtocol,
                        text: "\(g.id): \(g.title)",
                        c4Snapshot: c4,
                        terminalState: .calorie
                    )
                )
            }
            defaults.set(true, forKey: catalogIngestDefaultsKey)
        }

        let baselineProfile = FranklinProfile()
        let profileJSON = (try? String(data: JSONEncoder().encode(baselineProfile), encoding: .utf8)) ?? "{}"
        let smDigest = Self.sha256Hex(profileJSON.data(using: .utf8) ?? Data())

        await FranklinSubstrate.shared.insertSelfModelGenesisIfAbsent(
            id: genesisSelfModelRowID,
            version: 1,
            reason: "genesis",
            profileJSON: profileJSON,
            drift: 0,
            narrative: "",
            sha256: smDigest,
            timestampISO: awakenISO
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
