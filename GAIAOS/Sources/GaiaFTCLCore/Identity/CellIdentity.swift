import Foundation

public struct CellIdentity: Codable {
    public var wallet: String
    public var cellId: String
    public var status: String
    public var onboardedAt: String
    
    enum CodingKeys: String, CodingKey {
        case wallet
        case cellId = "cell_id"
        case status
        case onboardedAt = "onboarded_at"
    }
    
    public static func load() throws -> CellIdentity {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gaiaftcl/cell_identity.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CellIdentity.self, from: data)
    }
    
    public func save() throws {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gaiaftcl/cell_identity.json")
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }
}
