import ArgumentParser
import GaiaFTCLCore

struct StateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "state",
        abstract: "State operations",
        subcommands: [Close.self]
    )

    struct Close: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "close", abstract: "Terminal state writer")
        @Argument(help: "Terminal state (CALORIE|CURE|REFUSED)") var terminalState: String
        mutating func run() async throws { print("\(terminalState)\n{\"state_closed\": \"\(terminalState)\"}") }
    }
}
