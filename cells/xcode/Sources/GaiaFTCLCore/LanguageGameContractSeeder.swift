import Foundation
import GRDB

/// Inserts canonical **FUSION-001** / **HEALTH-001** rows (**`INSERT OR IGNORE`**) after migrations.
public enum LanguageGameContractSeeder {
    public static func seedCanonicalContracts(writer: any DatabaseWriter, timestampISO: String) throws {
        let repo = FranklinDocumentRepository(db: writer)
        let cellID = ProcessInfo.processInfo.environment["GAIAFTCL_CELL_ID"] ?? "gaiaftcl-mac-cell"
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let fusion = try LanguageGameContractSeed.fusionContract(createdAtISO: timestampISO)
        let fusionData = try enc.encode(fusion)
        try repo.insertLanguageGameContractIfAbsent(
            id: "lgc-\(LanguageGameContractSeed.fusionGameID)",
            gameID: fusion.game_id,
            cellID: cellID,
            domain: fusion.domain,
            contractDocJSON: String(data: fusionData, encoding: .utf8) ?? "{}",
            contractSha256: fusion.sha256,
            status: "active",
            timestampISO: timestampISO
        )
        let health = try LanguageGameContractSeed.healthContract(createdAtISO: timestampISO)
        let healthData = try enc.encode(health)
        try repo.insertLanguageGameContractIfAbsent(
            id: "lgc-\(LanguageGameContractSeed.healthGameID)",
            gameID: health.game_id,
            cellID: cellID,
            domain: health.domain,
            contractDocJSON: String(data: healthData, encoding: .utf8) ?? "{}",
            contractSha256: health.sha256,
            status: "active",
            timestampISO: timestampISO
        )
        try patchAestheticDefaultsIfNeeded(writer: writer)
    }

    /// **`INSERT OR IGNORE`** paths may omit **`aesthetic_rules_json`** — required before **`improveDomainStandard`** JSON decode.
    public static func patchAestheticDefaultsIfNeeded(writer: any DatabaseWriter) throws {
        let baseline = try AestheticRulesCodec.canonicalJSONString(.bootstrapDefaults())
        try writer.write { db in
            try db.execute(
                sql: """
                UPDATE language_game_contracts
                SET aesthetic_rules_json = ?
                WHERE aesthetic_rules_json IS NULL OR trim(aesthetic_rules_json) = ''
                """,
                arguments: [baseline]
            )
        }
    }
}
