import Foundation

public enum GAMPPhase: String, Codable, Sendable {
    case iq, oq, pq
}

public protocol GaiaFTCLTest: Sendable {
    var id: String { get }
    var name: String { get }
    var suite: String { get }
    var functionalRequirement: String { get }
    var phase: GAMPPhase { get }
    func execute() async throws -> Bool
}

public actor TestRobotEngine {
    public static let shared = TestRobotEngine()
    
    private var tests: [String: any GaiaFTCLTest] = [:]
    
    private init() {}
    
    public func register(_ test: any GaiaFTCLTest) {
        tests[test.id] = test
    }
    
    public func get(id: String) -> (any GaiaFTCLTest)? {
        return tests[id]
    }
    
    public func list() -> [any GaiaFTCLTest] {
        return Array(tests.values)
    }
    
    public func runAll() async throws -> Bool {
        var allPassed = true
        for test in tests.values {
            do {
                let passed = try await test.execute()
                if !passed { allPassed = false }
            } catch {
                allPassed = false
            }
        }
        return allPassed
    }
    
    public func run(id: String) async throws -> Bool {
        guard let test = tests[id] else { throw NSError(domain: "TestNotFound", code: 404) }
        return try await test.execute()
    }
}
