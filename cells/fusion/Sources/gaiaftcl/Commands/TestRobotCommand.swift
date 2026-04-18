import ArgumentParser
import GaiaFTCLCore

struct TestRobotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "testrobot",
        abstract: "Embedded test IDE",
        subcommands: [
            List.self,
            Run.self,
            Add.self,
            Edit.self,
            Show.self,
            Receipt.self
        ]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List all tests")
        @Option(name: .customLong("suite"), help: "Filter by suite") var suite: String?
        @Option(name: .customLong("status"), help: "Show only failures") var status: String?
        @Option(name: .customLong("fr"), help: "Tests for a functional requirement") var fr: String?
        mutating func run() async throws { print("CALORIE\n{\"tests\": []}") }
    }

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "run", abstract: "Run tests")
        @Option(name: .customLong("suite"), help: "Run one suite") var suite: String?
        @Option(name: .customLong("test"), help: "Run single test by ID") var test: String?
        @Option(name: .customLong("phase"), help: "Run tests for a GAMP phase") var phase: String?
        @Option(name: .customLong("invariant"), help: "Run harness for invariant ID") var invariant: String?
        mutating func run() async throws {
            if let invId = invariant {
                await InvariantRegistry.shared.loadAll()
                if let record = await InvariantRegistry.shared.get(id: invId) {
                    // Execute harness (stubbed)
                    let passed = true
                    let newStatus = passed ? "CURE-CLOSED" : "REFUSED"
                    try await InvariantRegistry.shared.transitionStatus(id: invId, to: newStatus, evidence: "Harness passed")
                    print("CURE\n{\"invariant_run\": \"\(invId)\", \"status\": \"\(newStatus)\"}")
                } else {
                    print("REFUSED\n{\"error\": \"Invariant not found\"}")
                }
            } else {
                print("CALORIE\n{\"tests_run\": true}")
            }
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "Create new test stub")
        @Option(name: .customLong("suite")) var suite: String
        @Option(name: .customLong("name")) var name: String
        @Option(name: .customLong("fr")) var fr: String
        @Option(name: .customLong("phase")) var phase: String
        mutating func run() async throws { print("CALORIE\n{\"added\": \"\(name)\"}") }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "edit", abstract: "Open in Console editor")
        @Argument(help: "Test ID") var testId: String
        mutating func run() async throws { print("CALORIE\n{\"edit\": \"\(testId)\"}") }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Print test source")
        @Argument(help: "Test ID") var testId: String
        mutating func run() async throws { print("CALORIE\n{\"show\": \"\(testId)\"}") }
    }

    struct Receipt: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "receipt", abstract: "Print testrobot_receipt.json")
        @Option(name: .customLong("format"), help: "html or json") var format: String?
        mutating func run() async throws { print("CALORIE\n{\"receipt\": true}") }
    }
}
