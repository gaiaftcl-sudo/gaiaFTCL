import ArgumentParser
import GaiaFTCLCore

@main
struct MainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gaiaftcl",
        abstract: "GaiaFTCL CLI - Canonical operator surface",
        subcommands: [
            CellCommand.self,
            FusionCommand.self,
            HealthCommand.self,
            MeshCommand.self,
            GateCommand.self,
            EvidenceCommand.self,
            StateCommand.self,
            TestRobotCommand.self,
            InvariantCommand.self,
            PathogenCommand.self
        ]
    )
}
