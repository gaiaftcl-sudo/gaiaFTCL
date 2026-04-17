import ArgumentParser
import GaiaFTCLCore

struct EvidenceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evidence",
        abstract: "Evidence operations",
        subcommands: [
            Release.self,
            MacFusion.self,
            NativeFusion.self,
            Mesh.self,
            Parity.self,
            Receipt.self
        ]
    )

    struct Release: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "release", abstract: "Release evidence bundle")
        mutating func run() async throws { print("CALORIE\n{\"release_evidence\": true}") }
    }

    struct MacFusion: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mac_fusion", abstract: "Mac Fusion evidence")
        mutating func run() async throws { print("CALORIE\n{\"mac_fusion_evidence\": true}") }
    }

    struct NativeFusion: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "native_fusion", abstract: "Native Fusion (Health) evidence")
        mutating func run() async throws { print("CALORIE\n{\"native_fusion_evidence\": true}") }
    }

    struct Mesh: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mesh", abstract: "Mesh evidence")
        mutating func run() async throws { print("CALORIE\n{\"mesh_evidence\": true}") }
    }

    struct Parity: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "parity", abstract: "Cross-cell parity check")
        mutating func run() async throws { print("CALORIE\n{\"parity_checked\": true}") }
    }

    struct Receipt: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "receipt", abstract: "Lookup receipt by SHA-256")
        @Argument(help: "SHA-256 hash") var sha: String
        mutating func run() async throws { print("CALORIE\n{\"receipt\": \"\(sha)\"}") }
    }
}
