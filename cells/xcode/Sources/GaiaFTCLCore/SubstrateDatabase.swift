import Foundation
import GRDB

/// Shared GRDB DatabasePool for the sovereign M8 substrate.
/// Path: ~/Library/Application Support/GaiaFTCL/substrate.sqlite
public actor SubstrateDatabase {
    public static let shared = SubstrateDatabase()

    private var _pool: DatabasePool?

    private init() {}

    public func pool() async throws -> DatabasePool {
        if let p = _pool { return p }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GaiaFTCL", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let dbURL = url.appendingPathComponent("substrate.sqlite")
        let p = try DatabasePool(path: dbURL.path)
        var migrator = DatabaseMigrator()
        createSubstrateMigrations(&migrator)
        try migrator.migrate(p)
        _pool = p
        return p
    }

    /// In-memory queue for tests — all migrations applied, no persistent state.
    public static func testQueue() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        createSubstrateMigrations(&migrator)
        try migrator.migrate(q)
        return q
    }
}
